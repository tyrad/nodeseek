#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "stringio"
require "tmpdir"

require_relative "generate-release-notes"

class ReleaseNotesGeneratorTest < Minitest::Test
  def git(dir, *args)
    stdout, stderr, status = Open3.capture3(
      {
        "GIT_AUTHOR_NAME" => "Test",
        "GIT_AUTHOR_EMAIL" => "test@example.com",
        "GIT_COMMITTER_NAME" => "Test",
        "GIT_COMMITTER_EMAIL" => "test@example.com"
      },
      "git", "-C", dir, *args
    )
    assert status.success?, "git #{args.join(' ')} failed: #{stderr}"
    stdout.strip
  end

  def create_commit(dir, file, content, message)
    File.write(File.join(dir, file), content)
    git(dir, "add", file)
    git(dir, "commit", "-m", message)
    git(dir, "rev-parse", "HEAD")
  end

  def with_temp_repo
    Dir.mktmpdir("release-notes-test") do |dir|
      git(dir, "init")
      yield dir
    end
  end

  def test_rebuild_uses_highest_reachable_lower_version
    with_temp_repo do |dir|
      create_commit(dir, "a.txt", "1", "feat(init): 初始化")
      git(dir, "tag", "ios/v1.3.1")
      git(dir, "tag", "ios/v1.3.1-build.20261111185129")

      create_commit(dir, "a.txt", "2", "fix(mail): 修复邮箱绑定")
      git(dir, "tag", "ios/v1.4.2-build.20261119064405")

      head = create_commit(dir, "a.txt", "3", "feat(hot-list): 新增热榜页")

      %w[ios/v1.5 ios/v1.5.0-build.1 ios/v1.6.0-build.2 ios/v1.3.9-build.3].each do |tag|
        git(dir, "tag", tag)
      end
      prev = ReleaseNotesGenerator.find_previous_tag(
        repo_dir: dir,
        commit: head,
        version: "1.5.0",
        exclude_tags: ["ios/v1.5.0", "ios/v1.5.0-build.20261125050000"]
      )
      assert_equal "ios/v1.4.2-build.20261119064405", prev
    end
  end

  def test_prefers_build_tag_over_bare_tag_on_same_commit
    with_temp_repo do |dir|
      create_commit(dir, "a.txt", "1", "feat(init): 初始化")
      git(dir, "tag", "ios/v1.3.1")
      git(dir, "tag", "ios/v1.3.1-build.20261111185129")

      head = create_commit(dir, "a.txt", "2", "fix(detail): 修复排版")
      prev = ReleaseNotesGenerator.find_previous_tag(
        repo_dir: dir,
        commit: head,
        version: "1.3.2",
        exclude_tags: ["ios/v1.3.2-build.20261112000000"]
      )
      assert_equal "ios/v1.3.1-build.20261111185129", prev
    end
  end

  def test_prefers_latest_build_when_multiple_builds_share_commit
    with_temp_repo do |dir|
      sha = create_commit(dir, "a.txt", "1", "feat(init): 初始化")
      git(dir, "tag", "ios/v1.4.1-build.20261117233815")
      git(dir, "tag", "ios/v1.4.1-build.20261117235621")

      prev = ReleaseNotesGenerator.find_previous_tag(
        repo_dir: dir,
        commit: sha,
        version: "1.4.2"
      )
      assert_equal "ios/v1.4.1-build.20261117235621", prev
    end
  end

  def test_groups_user_changes_and_collapses_engineering_commits
    with_temp_repo do |dir|
      create_commit(dir, "a.txt", "1", "feat(init): 初始化")
      git(dir, "tag", "ios/v1.4.2-build.20261119064405")

      create_commit(dir, "b.txt", "1", "feat(hot-list): 新增热榜页")
      create_commit(dir, "c.txt", "1", "ui(hot-list): 榜单切换移到导航栏")
      create_commit(dir, "d.txt", "1", "perf(me): 直接调用资料保存接口")
      create_commit(dir, "e.txt", "1", "fix(detail): 修复翻页空白")
      create_commit(dir, "f.txt", "1", "revert(home): 撤回发帖按钮淡出")
      create_commit(dir, "g.txt", "1", "docs(hot-list): 补充接口实测文档")
      create_commit(dir, "h.txt", "1", "test(detail): 补充深链回归用例")
      create_commit(dir, "i.txt", "1", "build(release): 版本号升至 1.5.0")
      head = create_commit(dir, "j.txt", "1", "临时调整文案")

      notes = ReleaseNotesGenerator.generate(
        repo_dir: dir,
        version: "1.5.0",
        build_number: "20261125050000",
        source_ref: "main (workflow_dispatch)",
        release_tag: "ios/v1.5.0-build.20261125050000",
        commit: head,
        repository: "tyrad/nodeseek",
        exclude_tags: ["main"]
      )

      assert_includes notes, "- Previous tag: ios/v1.4.2-build.20261119064405"
      assert_includes notes, "### 新功能\n\n- **hot-list**：新增热榜页"
      assert_includes notes, "### 界面与体验\n\n- **me**：直接调用资料保存接口"
      assert_includes notes, "- **hot-list**：榜单切换移到导航栏"
      assert_includes notes, "### 问题修复\n\n- **home**：撤回发帖按钮淡出"
      assert_includes notes, "- **detail**：修复翻页空白"
      assert_includes notes, "### 其他变更\n\n- 临时调整文案"
      assert_includes notes, "<details>\n<summary>工程与文档变更（3 条）</summary>"
      assert_includes notes, "- `build(release)` 版本号升至 1.5.0"
      assert_includes notes, "- `test(detail)` 补充深链回归用例"
      assert_includes notes, "- `docs(hot-list)` 补充接口实测文档"
      assert_includes notes, "**Full Changelog**: https://github.com/tyrad/nodeseek/compare/ios/v1.4.2-build.20261119064405...ios/v1.5.0-build.20261125050000"
    end
  end

  def test_ai_summary_with_deepseek_merges_changes_and_collapses_all_raw_commits
    with_temp_repo do |dir|
      create_commit(dir, "a.txt", "1", "feat(init): 初始化")
      git(dir, "tag", "ios/v1.4.2-build.20261119064405")

      create_commit(dir, "b.txt", "1", "feat(hot-list): 新增热榜页")
      git(dir, "tag", "ios/v1.5.0-build.100")
      create_commit(dir, "c.txt", "1", "fix(hot-list): 修复热榜设置页箭头缺失")
      head = create_commit(dir, "d.txt", "1", "docs(hot-list): 记录热榜方案")

      captured_requests = []
      fake_http = lambda do |uri:, headers:, payload:, timeout:|
        captured_requests << { uri: uri.to_s, headers: headers, payload: payload, timeout: timeout }
        body = JSON.generate(
          choices: [
            {
              message: {
                content: "```markdown\n### 新功能\n\n- **热榜**：新增热榜页及对应设置入口\n```"
              }
            }
          ]
        )
        [200, body]
      end

      ai_config = ReleaseNotesGenerator::AIConfig.new(
        enabled: true,
        api_base: ReleaseNotesGenerator::DEFAULT_API_BASE,
        model: ReleaseNotesGenerator::DEFAULT_MODEL,
        api_key: "sk-deepseek-test",
        timeout: 30
      )

      notes = ReleaseNotesGenerator.generate(
        repo_dir: dir,
        version: "1.5.0",
        build_number: "20261125050000",
        source_ref: "main (workflow_dispatch)",
        release_tag: "ios/v1.5.0-build.20261125050000",
        commit: head,
        repository: "tyrad/nodeseek",
        ai_config: ai_config,
        http_requester: fake_http
      )

      assert_equal 1, captured_requests.length
      req = captured_requests.first
      assert_equal "https://api.deepseek.com/v1/chat/completions", req[:uri]
      assert_equal "Bearer sk-deepseek-test", req[:headers]["Authorization"]
      assert_equal "application/json", req[:headers]["Accept"]
      assert_equal "deepseek-flash", req[:payload][:model]
      assert_equal({ type: "disabled" }, req[:payload][:thinking])

      # 验证发给模型的提交按时间从早到晚排列，且过滤掉了 docs 提交
      user_msg = req[:payload][:messages][1][:content]
      assert_operator user_msg.index("feat(hot-list)"), :<, user_msg.index("fix(hot-list)")
      refute_includes user_msg, "docs(hot-list)"

      # 验证输出已去除 markdown 围栏，且折叠全部原始提交（含工程文档类）
      assert_includes notes, "## Changes\n\n### 新功能\n\n- **热榜**：新增热榜页及对应设置入口"
      refute_includes notes, "```markdown"
      assert_includes notes, "<details>\n<summary>完整提交记录（3 条）</summary>"
      assert_includes notes, "- `docs(hot-list)` 记录热榜方案"
      assert_includes notes, "- `fix(hot-list)` 修复热榜设置页箭头缺失"
      assert_includes notes, "- `feat(hot-list)` 新增热榜页"
    end
  end

  def test_missing_api_key_silently_skips_ai_and_uses_rule_based_notes
    with_temp_repo do |dir|
      create_commit(dir, "a.txt", "1", "feat(init): 初始化")
      git(dir, "tag", "ios/v1.4.2-build.20261119064405")

      create_commit(dir, "b.txt", "1", "feat(hot-list): 新增热榜页")
      head = create_commit(dir, "c.txt", "1", "fix(detail): 修复翻页问题")

      called = false
      fake_http = lambda do |**|
        called = true
        [200, "{}"]
      end

      warn_buf = StringIO.new
      ai_config = ReleaseNotesGenerator::AIConfig.new(
        enabled: true,
        api_base: ReleaseNotesGenerator::DEFAULT_API_BASE,
        model: ReleaseNotesGenerator::DEFAULT_MODEL,
        api_key: "",
        timeout: 10
      )

      notes = ReleaseNotesGenerator.generate(
        repo_dir: dir,
        version: "1.5.0",
        build_number: "20261125050000",
        source_ref: "main (workflow_dispatch)",
        release_tag: "ios/v1.5.0-build.20261125050000",
        commit: head,
        ai_config: ai_config,
        http_requester: fake_http,
        warn_io: warn_buf
      )

      refute called, "未配置 API Key 时不应发起 HTTP 请求"
      assert_equal "", warn_buf.string
      assert_includes notes, "### 新功能\n\n- **hot-list**：新增热榜页"
      assert_includes notes, "### 问题修复\n\n- **detail**：修复翻页问题"
    end
  end

  def test_ai_failure_gracefully_falls_back_to_rule_based_notes
    with_temp_repo do |dir|
      create_commit(dir, "a.txt", "1", "feat(init): 初始化")
      git(dir, "tag", "ios/v1.4.2-build.20261119064405")

      create_commit(dir, "b.txt", "1", "feat(hot-list): 新增热榜页")
      create_commit(dir, "c.txt", "1", "fix(detail): 修复翻页问题")
      head = create_commit(dir, "d.txt", "1", "docs(hot-list): 补充文档")

      fake_http = lambda do |**|
        raise Timeout::Error, "execution expired"
      end

      warn_buf = StringIO.new
      ai_config = ReleaseNotesGenerator::AIConfig.new(
        enabled: true,
        api_base: ReleaseNotesGenerator::DEFAULT_API_BASE,
        model: ReleaseNotesGenerator::DEFAULT_MODEL,
        api_key: "sk-deepseek-test",
        timeout: 5
      )

      notes = ReleaseNotesGenerator.generate(
        repo_dir: dir,
        version: "1.5.0",
        build_number: "20261125050000",
        source_ref: "main (workflow_dispatch)",
        release_tag: "ios/v1.5.0-build.20261125050000",
        commit: head,
        ai_config: ai_config,
        http_requester: fake_http,
        warn_io: warn_buf
      )

      assert_includes warn_buf.string, "falling back to rule-based notes"
      assert_includes notes, "### 新功能\n\n- **hot-list**：新增热榜页"
      assert_includes notes, "### 问题修复\n\n- **detail**：修复翻页问题"
      assert_includes notes, "<summary>工程与文档变更（1 条）</summary>"
    end
  end

  def test_accepts_alternative_bullets_and_rejects_truncated_output
    assert_equal "- 相同内容", ReleaseNotesGenerator.sanitize_ai_summary("* 相同内容")
    config = ReleaseNotesGenerator::AIConfig.new(enabled: true, api_base: "https://example.com", api_key: "test")
    commits = %w[功能一 功能二].map { |s| ReleaseNotesGenerator::Commit.new(subject: s) }
    requester = lambda do |payload:, **|
      refute payload.key?(:thinking)
      [200, JSON.generate(choices: [{ finish_reason: "length", message: { content: "- 半段文本" } }])]
    end
    log = StringIO.new
    assert_nil ReleaseNotesGenerator.summarize_with_ai(version: "1.0", previous_tag: nil, user_commits: commits,
      ai_config: config, http_requester: requester, warn_io: log)
    assert_includes log.string, "stopped with length"
  end

  def test_large_fallback_collapses_commit_details
    commits = (1..16).map { |i| ReleaseNotesGenerator::Commit.new(short_sha: i.to_s, subject: "fix(feed): 修复条目 #{i}") }
    notes = ReleaseNotesGenerator.render(version: "2.0", build_number: "9", source_ref: "main",
      release_tag: "ios/v2.0-build.9", commit: "abc", previous_tag: nil, commits: commits)
    summary, details = notes.split("<details>")
    assert_includes summary, "问题修复 16 条"
    refute_includes summary, "修复条目"
    assert_includes details, "完整提交记录（16 条）"
    assert_includes details, "修复条目 16"
  end

  def test_single_user_commit_skips_ai_call
    with_temp_repo do |dir|
      create_commit(dir, "a.txt", "1", "feat(init): 初始化")
      git(dir, "tag", "ios/v1.4.1-build.20261118184746")

      create_commit(dir, "b.txt", "1", "docs(privacy): 更新隐私政策")
      head = create_commit(dir, "c.txt", "1", "fix(mail): 修复邮箱绑定崩溃")

      called = false
      fake_http = lambda do |**|
        called = true
        [200, "{}"]
      end

      ai_config = ReleaseNotesGenerator::AIConfig.new(
        enabled: true,
        api_base: ReleaseNotesGenerator::DEFAULT_API_BASE,
        model: ReleaseNotesGenerator::DEFAULT_MODEL,
        api_key: "sk-deepseek-test",
        timeout: 10
      )

      notes = ReleaseNotesGenerator.generate(
        repo_dir: dir,
        version: "1.4.2",
        build_number: "20261119064405",
        source_ref: "main (workflow_dispatch)",
        release_tag: "ios/v1.4.2-build.20261119064405",
        commit: head,
        ai_config: ai_config,
        http_requester: fake_http
      )

      refute called, "单条用户提交不应触发 AI 调用"
      assert_includes notes, "### 问题修复\n\n- **mail**：修复邮箱绑定崩溃"
      assert_includes notes, "<summary>工程与文档变更（1 条）</summary>"
    end
  end

  def test_chat_completions_uri_handles_both_base_and_full_endpoint
    assert_equal(
      "https://api.deepseek.com/v1/chat/completions",
      ReleaseNotesGenerator.chat_completions_uri("https://api.deepseek.com/v1/").to_s
    )
    assert_equal(
      "https://example.com/v1/chat/completions",
      ReleaseNotesGenerator.chat_completions_uri("https://example.com/v1/chat/completions").to_s
    )
  end

  def test_ai_prompt_truncates_oldest_commits_when_over_budget
    long_commits = (1..400).map do |i|
      ReleaseNotesGenerator::Commit.new(short_sha: format("%07x", i), subject: "fix(detail): 第 #{i} 条较长的提交说明用于测试输入预算控制与截断行为")
    end
    prompt = ReleaseNotesGenerator.build_ai_user_prompt(
      version: "1.5.0",
      previous_tag: "ios/v1.4.2-build.20261119064405",
      commits: long_commits
    )
    assert_includes prompt, "已截断"
    assert_includes prompt, "第 1 条"
    refute_includes prompt, "第 400 条"
    assert_operator prompt.length, :<, ReleaseNotesGenerator::MAX_AI_INPUT_CHARS + 500
  end

  def test_first_version_rebuild_keeps_all_features
    with_temp_repo do |dir|
      sha = create_commit(dir, "a.txt", "1", "feat(init): 初始化")
      git(dir, "tag", "ios/v1.4.2-build.20261119064405")

      notes = ReleaseNotesGenerator.generate(
        repo_dir: dir,
        version: "1.4.2",
        build_number: "20261125050000",
        source_ref: "main (workflow_dispatch)",
        release_tag: "ios/v1.4.2-build.20261125050000",
        commit: sha,
        repository: "tyrad/nodeseek"
      )

      assert_includes notes, "- Previous tag: none"
      assert_includes notes, "初始化"
      refute_includes notes, "<details>"
    end
  end

  def test_engineering_only_release_shows_fallback_hint_and_details
    with_temp_repo do |dir|
      create_commit(dir, "a.txt", "1", "feat(init): 初始化")
      git(dir, "tag", "ios/v1.4.2-build.20261119064405")

      head = create_commit(dir, "b.txt", "1", "ci(testflight): 调整打包脚本")
      notes = ReleaseNotesGenerator.generate(
        repo_dir: dir,
        version: "1.4.3",
        build_number: "20261125050000",
        source_ref: "main (workflow_dispatch)",
        release_tag: "ios/v1.4.3-build.20261125050000",
        commit: head,
        repository: "tyrad/nodeseek"
      )

      assert_includes notes, "本次构建无面向用户的功能变更，详见下方工程与文档变更。"
      assert_includes notes, "<summary>工程与文档变更（1 条）</summary>"
      assert_includes notes, "- `ci(testflight)` 调整打包脚本"
    end
  end

  def test_first_release_without_previous_tag
    with_temp_repo do |dir|
      head = create_commit(dir, "a.txt", "1", "feat(app): 首个版本")
      notes = ReleaseNotesGenerator.generate(
        repo_dir: dir,
        version: "1.0.0",
        build_number: "20261125050000",
        source_ref: "ios/v1.0.0",
        release_tag: "ios/v1.0.0-build.20261125050000",
        commit: head,
        repository: "tyrad/nodeseek",
        exclude_tags: ["ios/v1.0.0"]
      )

      assert_includes notes, "- Previous tag: none"
      assert_includes notes, "### 新功能\n\n- **app**：首个版本"
      refute_includes notes, "Full Changelog"
    end
  end
end

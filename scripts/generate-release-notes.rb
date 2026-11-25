#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "open3"
require "optparse"
require "uri"

# 根据 Git 历史生成 GitHub Release 说明：
# - 以当前提交可达的上一版本最后一个构建为基线，同版本重复打包仍生成完整更新说明
# - 配置 API Key 时（默认 DeepSeek OpenAI 兼容接口），自动合并未上线功能迭代与开发期修复，并剔除已撤回的中间过程
# - 原始提交（含工程与文档类）统一折叠保留；未配置 Key 或调用失败时自动降级为规则分组，不阻塞打包
module ReleaseNotesGenerator
  RELEASE_TAG_PATTERN = /\Aios\/v(\d+(?:\.\d+){1,2})(?:-build\.(\d+))?\z/.freeze
  COMMIT_SUBJECT_PATTERN = /\A([a-zA-Z][a-zA-Z0-9_-]*)(?:\(([^)]*)\))?(!)?:\s*(.+)\z/.freeze

  DEFAULT_API_BASE = "https://api.deepseek.com/v1"
  DEFAULT_MODEL = "deepseek-flash"
  DEFAULT_TIMEOUT_SECONDS = 45
  MAX_AI_INPUT_CHARS = 12_000

  USER_GROUPS = [
    { key: :feat, title: "新功能", types: %w[feat] },
    { key: :experience, title: "界面与体验", types: %w[ui perf] },
    { key: :fix, title: "问题修复", types: %w[fix revert] },
    { key: :other, title: "其他变更", types: [] }
  ].freeze

  ENGINEERING_TYPES = %w[refactor build ci test docs chore style].freeze

  SYSTEM_PROMPT = <<~PROMPT.strip
    你是 iOS 客户端「NS Connect（NodeSeek 非官方客户端）」的发版说明整理助手。
    请根据按时间从早到晚排列的 Git 提交记录，提炼一份清晰、精炼、面向终端用户的中文 GitHub Release 更新说明。

    必须遵守以下规则：
    1. 严格基于输入提交总结，禁止编造提交中不存在的功能或修复。
    2. 合并未上线功能的迭代：如果某个功能是在本次发布周期内新开发并首次上线的（例如新增的页面、深链、新版详情页引擎等），请把该功能后续的样式调整、性能优化、开发期 bug 修复合并进对应的功能条目中，不要把未上线功能的开发期修补拆成独立的问题修复。
    3. 剔除被覆盖或撤回的中间尝试：若后提交撤回或推翻了前提交（例如先改成方案 A 后撤回恢复原样，或先改为弹窗后改为行内展开），只保留最终生效的结果；完全抵消的改动直接省略。
    4. 过滤非面向用户内容：忽略内测打包口令、调试开关、开发/测试辅助入口；避免堆砌内部实现术语（如 TextKit、Texture、缓存键等），尽量写用户可感知的变化。
    5. 输出格式要求：
       - 只输出 Markdown 变更正文，不要包含开场白、结语、代码块围栏（如 ```markdown）、`## Build`、`## Changes` 或 `Full Changelog`。
       - 仅按需使用以下三个三级标题（没有内容的小节不要输出）：
         ### 新功能
         ### 体验优化
         ### 问题修复
       - 每条使用 `- **模块名**：简洁说明`（模块名用自然中文，如「热榜」「详情页」「个人主页」「深链」「搜索」「首页」等），不要附带 commit hash。
       - 先写能直接使用的新功能，每条说明入口或使用效果，保留 Beta 等状态。相同功能只写一次；一个大版本通常 5～8 条，小版本按实际内容写。
  PROMPT

  Commit = Struct.new(:short_sha, :subject, keyword_init: true)
  ParsedCommit = Struct.new(:short_sha, :type, :scope, :breaking, :summary, :raw_subject, keyword_init: true)
  AIConfig = Struct.new(:enabled, :api_base, :model, :api_key, :timeout, keyword_init: true)

  module_function

  def run_git(repo_dir, *args)
    stdout, stderr, status = Open3.capture3("git", "-C", repo_dir, *args)
    unless status.success?
      raise "git #{args.join(' ')} failed (exit #{status.exitstatus}): #{stderr.strip}"
    end
    stdout
  end

  def find_previous_tag(repo_dir:, commit:, version:, exclude_tags: [])
    current_version = Gem::Version.new(version)
    tags = run_git(repo_dir, "tag", "--merged", commit, "--list", "ios/v*")

    candidates = tags.lines.map do |line|
      tag = line.chomp
      match = RELEASE_TAG_PATTERN.match(tag)
      next unless match && !exclude_tags.include?(tag)

      tag_version = Gem::Version.new(match[1])
      next unless tag_version < current_version

      # 同一版本优先取最大构建号；只有裸版本标签时也能作为基线。
      [tag_version, match[2] ? match[2].to_i : -1, tag]
    end

    candidates.compact.max&.last
  end

  def list_commits(repo_dir:, commit:, previous_tag:)
    range = previous_tag ? "#{previous_tag}..#{commit}" : commit
    output = run_git(repo_dir, "log", "--no-merges", "--format=%h%x1f%s", range)
    commits = []
    output.each_line do |line|
      stripped = line.chomp
      next if stripped.empty?

      short_sha, subject = stripped.split("\x1f", 2)
      next if short_sha.nil? || subject.nil?

      commits << Commit.new(short_sha: short_sha, subject: subject.strip)
    end
    commits
  end

  def parse_commit(commit)
    match = COMMIT_SUBJECT_PATTERN.match(commit.subject)
    if match
      type = match[1].downcase
      scope = match[2]&.strip
      scope = nil if scope && scope.empty?
      ParsedCommit.new(
        short_sha: commit.short_sha,
        type: type,
        scope: scope,
        breaking: !match[3].nil?,
        summary: match[4].strip,
        raw_subject: commit.subject
      )
    else
      ParsedCommit.new(
        short_sha: commit.short_sha,
        type: nil,
        scope: nil,
        breaking: false,
        summary: commit.subject,
        raw_subject: commit.subject
      )
    end
  end

  def group_commits(commits)
    grouped = {
      feat: [],
      experience: [],
      fix: [],
      other: [],
      engineering: []
    }

    commits.each do |commit|
      parsed = parse_commit(commit)
      if parsed.type && ENGINEERING_TYPES.include?(parsed.type)
        grouped[:engineering] << parsed
        next
      end

      matched_group = USER_GROUPS.find { |group| parsed.type && group[:types].include?(parsed.type) }
      if matched_group
        grouped[matched_group[:key]] << parsed
      else
        grouped[:other] << parsed
      end
    end

    grouped
  end

  def user_facing_commits(commits)
    commits.reject do |commit|
      parsed = parse_commit(commit)
      parsed.type && ENGINEERING_TYPES.include?(parsed.type)
    end
  end

  def format_user_item(parsed)
    breaking_prefix = parsed.breaking ? "⚠️ " : ""
    if parsed.scope
      "- **#{parsed.scope}**：#{breaking_prefix}#{parsed.summary} (`#{parsed.short_sha}`)"
    else
      "- #{breaking_prefix}#{parsed.summary} (`#{parsed.short_sha}`)"
    end
  end

  def format_raw_commit_item(commit)
    parsed = parse_commit(commit)
    if parsed.type
      label = parsed.scope ? "#{parsed.type}(#{parsed.scope})" : parsed.type
      "- `#{label}` #{parsed.summary} (`#{parsed.short_sha}`)"
    else
      "- #{parsed.raw_subject} (`#{parsed.short_sha}`)"
    end
  end

  def format_engineering_item(parsed)
    label = parsed.scope ? "#{parsed.type}(#{parsed.scope})" : parsed.type
    "- `#{label}` #{parsed.summary} (`#{parsed.short_sha}`)"
  end

  def chat_completions_uri(api_base)
    normalized = api_base.to_s.strip.sub(%r{/+\z}, "")
    endpoint = normalized.end_with?("/chat/completions") ? normalized : "#{normalized}/chat/completions"
    URI.parse(endpoint)
  end

  def resolved_model(ai_config)
    configured = ai_config.model.to_s.strip
    configured.empty? ? DEFAULT_MODEL : configured
  end

  def build_ai_user_prompt(version:, previous_tag:, commits:)
    # 按时间从早到晚排列，方便模型识别“先新增功能、后修开发期 bug”以及“先改后撤回”的演进关系
    chronological = commits.reverse
    lines = chronological.map { |commit| "- #{commit.subject}" }

    omitted = 0
    joined = lines.join("\n")
    while joined.length > MAX_AI_INPUT_CHARS && lines.length > 1
      lines.shift
      omitted += 1
      joined = lines.join("\n")
    end

    header = []
    header << "当前发布版本：v#{version}"
    header << "上一版本基线：#{previous_tag || '无（首次发布）'}"
    header << "提交记录（已过滤纯测试/文档/构建提交，按时间从早到晚排列#{omitted > 0 ? "，过早的 #{omitted} 条已截断" : ""}）："
    "#{header.join("\n")}\n\n#{joined}"
  end

  def sanitize_ai_summary(raw_text)
    return nil if raw_text.nil?

    text = raw_text.to_s.strip
    # 去掉模型偶尔附加的外层代码块围栏
    if text.start_with?("```") && text.end_with?("```")
      text = text.sub(/\A```[a-zA-Z0-9_-]*\s*\n/, "").sub(/\n```\s*\z/, "").strip
    end
    # 去掉重复的顶层 Changes 标题
    text = text.sub(/\A##\s+Changes\s*\n+/i, "").strip
    return nil if text.empty?
    text = text.gsub(/^[ \t]*[*•][ \t]+/, "- ")
    return nil unless text.match?(/^- /m)

    text
  end

  def default_http_post(uri:, headers:, payload:, timeout:)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = timeout
    http.read_timeout = timeout

    request = Net::HTTP::Post.new(uri.request_uri)
    headers.each { |key, value| request[key] = value }
    request.body = JSON.generate(payload)

    response = http.request(request)
    [response.code.to_i, response.body.to_s]
  end

  def summarize_with_ai(version:, previous_tag:, user_commits:, ai_config:, http_requester: nil, warn_io: $stderr)
    return nil unless ai_config && ai_config.enabled
    return nil if ai_config.api_key.to_s.strip.empty?
    return nil if user_commits.length < 2

    api_base = ai_config.api_base.to_s.strip
    api_base = DEFAULT_API_BASE if api_base.empty?
    uri = chat_completions_uri(api_base)
    model_name = resolved_model(ai_config)
    timeout = (ai_config.timeout || DEFAULT_TIMEOUT_SECONDS).to_i
    requester = http_requester || method(:default_http_post)
    user_prompt = build_ai_user_prompt(version: version, previous_tag: previous_tag, commits: user_commits)

    payload = {
      model: model_name,
      temperature: 0.2,
      max_tokens: 2500,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: user_prompt }
      ]
    }
    # DeepSeek 默认先生成推理内容，短摘要只需把输出预算留给正文。
    payload[:thinking] = { type: "disabled" } if uri.host == "api.deepseek.com"

    begin
      status_code, body = requester.call(
        uri: uri,
        headers: {
          "Content-Type" => "application/json",
          "Accept" => "application/json",
          "Authorization" => "Bearer #{ai_config.api_key.strip}"
        },
        payload: payload,
        timeout: timeout
      )

      unless status_code >= 200 && status_code < 300
        snippet = body.gsub(/\s+/, " ")[0, 200]
        raise "model #{model_name} returned HTTP #{status_code}: #{snippet}"
      end

      parsed = JSON.parse(body)
      finish_reason = parsed.dig("choices", 0, "finish_reason")
      raise "model #{model_name} stopped with #{finish_reason}" if finish_reason && finish_reason != "stop"

      content = parsed.dig("choices", 0, "message", "content")
      cleaned = sanitize_ai_summary(content)
      return cleaned if cleaned

      raise "model #{model_name} returned empty or invalid markdown (finish_reason=#{finish_reason.inspect}, content_chars=#{content.to_s.length})"
    rescue StandardError => e
      warn_io.puts("[release-notes] AI summarization unavailable (#{e.class}: #{e.message}), falling back to rule-based notes.") if warn_io
      nil
    end
  end

  def render(version:, build_number:, source_ref:, release_tag:, commit:, previous_tag:, commits:, repository: nil, ai_summary: nil)
    lines = []
    lines << "## Build"
    lines << ""
    lines << "- Version: #{version}"
    lines << "- Build number: #{build_number}"
    lines << "- Source ref: #{source_ref}"
    lines << "- Previous tag: #{previous_tag || 'none'}"
    lines << "- Commit: #{commit}"
    lines << ""
    lines << "## Changes"
    lines << ""

    if commits.empty?
      if previous_tag
        lines << "与上一版本（`#{previous_tag}`）代码一致，无新增提交。"
      else
        lines << "无新增提交。"
      end
    elsif ai_summary || user_facing_commits(commits).size > 15
      if ai_summary
        lines << ai_summary.strip
      else
        groups = group_commits(commits)
        counts = USER_GROUPS.map do |group|
          count = groups.fetch(group[:key]).size
          "#{group[:title]} #{count} 条" if count.positive?
        end
        lines << "本次变更按提交统计：#{counts.compact.join('、')}。"
      end
      lines << ""
      lines << "<details>"
      lines << "<summary>完整提交记录（#{commits.length} 条）</summary>"
      lines << ""
      commits.each { |item| lines << format_raw_commit_item(item) }
      lines << ""
      lines << "</details>"
      lines << ""
    else
      grouped = group_commits(commits)
      user_sections_rendered = false

      USER_GROUPS.each do |group|
        items = grouped[group[:key]]
        next if items.empty?

        user_sections_rendered = true
        lines << "### #{group[:title]}"
        lines << ""
        items.each { |item| lines << format_user_item(item) }
        lines << ""
      end

      unless user_sections_rendered
        lines << "本次构建无面向用户的功能变更，详见下方工程与文档变更。"
        lines << ""
      end

      engineering = grouped[:engineering]
      unless engineering.empty?
        lines << "<details>"
        lines << "<summary>工程与文档变更（#{engineering.length} 条）</summary>"
        lines << ""
        engineering.each { |item| lines << format_engineering_item(item) }
        lines << ""
        lines << "</details>"
        lines << ""
      end
    end

    if previous_tag && repository && !repository.empty?
      lines << "" unless lines.last == ""
      lines << "**Full Changelog**: https://github.com/#{repository}/compare/#{previous_tag}...#{release_tag}"
    end

    "#{lines.join("\n").rstrip}\n"
  end

  def generate(
    repo_dir:,
    version:,
    build_number:,
    source_ref:,
    release_tag:,
    commit:,
    repository: nil,
    exclude_tags: [],
    ai_config: nil,
    http_requester: nil,
    warn_io: $stderr
  )
    previous_tag = find_previous_tag(
      repo_dir: repo_dir,
      commit: commit,
      version: version,
      exclude_tags: exclude_tags + [release_tag]
    )
    commits = list_commits(repo_dir: repo_dir, commit: commit, previous_tag: previous_tag)
    user_commits = user_facing_commits(commits)
    ai_summary = summarize_with_ai(
      version: version,
      previous_tag: previous_tag,
      user_commits: user_commits,
      ai_config: ai_config,
      http_requester: http_requester,
      warn_io: warn_io
    )

    render(
      version: version,
      build_number: build_number,
      source_ref: source_ref,
      release_tag: release_tag,
      commit: commit,
      previous_tag: previous_tag,
      commits: commits,
      repository: repository,
      ai_summary: ai_summary
    )
  end
end

if __FILE__ == $PROGRAM_NAME
  env_ai_enabled = ENV["RELEASE_NOTES_AI_ENABLED"].to_s.downcase == "true"
  options = {
    repo_dir: ".",
    exclude_tags: [],
    ai_enabled: env_ai_enabled,
    api_base: ENV["RELEASE_NOTES_API_BASE"] || ReleaseNotesGenerator::DEFAULT_API_BASE,
    model: ENV["RELEASE_NOTES_MODEL"] || ReleaseNotesGenerator::DEFAULT_MODEL,
    api_key: ENV["RELEASE_NOTES_API_KEY"],
    timeout: (ENV["RELEASE_NOTES_AI_TIMEOUT"] || ReleaseNotesGenerator::DEFAULT_TIMEOUT_SECONDS).to_i
  }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby scripts/generate-release-notes.rb [options]"

    opts.on("--version VERSION", "Release marketing version") { |v| options[:version] = v }
    opts.on("--build-number BUILD_NUMBER", "Release build number") { |v| options[:build_number] = v }
    opts.on("--source-ref REF", "Source ref description") { |v| options[:source_ref] = v }
    opts.on("--release-tag TAG", "Target release tag") { |v| options[:release_tag] = v }
    opts.on("--commit SHA", "Target commit SHA or ref") { |v| options[:commit] = v }
    opts.on("--repository REPO", "GitHub repository owner/name") { |v| options[:repository] = v }
    opts.on("--exclude-tag TAG", "Tag to exclude when searching previous tag (repeatable)") do |v|
      options[:exclude_tags] << v
    end
    opts.on("--repo-dir DIR", "Git repository directory (default: .)") { |v| options[:repo_dir] = v }
    opts.on("--output PATH", "Output file path (defaults to stdout)") { |v| options[:output] = v }
    opts.on("--[no-]ai", "Enable or disable AI summarization (default: RELEASE_NOTES_AI_ENABLED=true)") do |v|
      options[:ai_enabled] = v
    end
    opts.on("--api-base URL", "OpenAI-compatible API base URL") { |v| options[:api_base] = v }
    opts.on("--model MODEL", "Model ID for AI summarization") { |v| options[:model] = v }
    opts.on("--timeout SECONDS", Integer, "HTTP timeout seconds for AI call") { |v| options[:timeout] = v }
  end

  parser.parse!(ARGV)

  required = %i[version build_number source_ref release_tag commit]
  missing = required.select { |key| options[key].nil? || options[key].empty? }
  unless missing.empty?
    warn "Missing required options: #{missing.map { |k| "--#{k.to_s.tr('_', '-')}" }.join(', ')}"
    warn parser.to_s
    exit 1
  end

  ai_config = ReleaseNotesGenerator::AIConfig.new(
    enabled: options[:ai_enabled],
    api_base: options[:api_base],
    model: options[:model],
    api_key: options[:api_key],
    timeout: options[:timeout]
  )

  notes = ReleaseNotesGenerator.generate(
    repo_dir: options[:repo_dir],
    version: options[:version],
    build_number: options[:build_number],
    source_ref: options[:source_ref],
    release_tag: options[:release_tag],
    commit: options[:commit],
    repository: options[:repository],
    exclude_tags: options[:exclude_tags],
    ai_config: ai_config
  )

  if options[:output]
    File.write(options[:output], notes, mode: "w:UTF-8")
  else
    $stdout.write(notes)
  end
end

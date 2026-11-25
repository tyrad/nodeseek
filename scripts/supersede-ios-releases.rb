# frozen_string_literal: true

require "json"
require "open3"

module SupersededReleases
  PREFIX = "【已被新版替代】"
  MARKER = "<!-- superseded-ios-build -->"

  module_function

  def downloadable?(release)
    assets = release.fetch("assets").select { |asset| asset["state"] == "uploaded" }.map { |asset| asset["name"] }
    assets.include?("nodeseek.ipa") && assets.include?("build-provenance.json") &&
      assets.any? { |name| name.end_with?(".dSYM.zip") }
  end

  def each_update(releases, version)
    tag_pattern = /\Aios\/v#{Regexp.escape(version)}-build\.(\d+)\z/
    builds = releases.each_with_object({}) do |release, result|
      match = tag_pattern.match(release.fetch("tag_name"))
      result[release] = match[1].to_i if match && !release["draft"]
    end

    # 任务可能乱序完成，始终以附件齐全的最高构建号作为替代目标。
    latest, latest_number = builds.select { |release, _| downloadable?(release) }.max_by(&:last)
    raise "找不到 v#{version} 可下载的构建" unless latest

    notice = "#{MARKER}\n> 此构建已被替代。[下载 v#{version} 最新构建（#{latest_number}）](#{latest.fetch('html_url')})\n\n"
    builds.each do |release, number|
      next unless number < latest_number

      title = release["name"].to_s
      title = release.fetch("tag_name") if title.empty?
      body = release["body"].to_s.sub(/\A#{Regexp.escape(MARKER)}\r?\n> [^\n]*\r?\n\r?\n/, "")
      update = { "name" => PREFIX + title.delete_prefix(PREFIX), "body" => notice + body }
      next if release["name"] == update["name"] && release["body"] == update["body"]

      yield release.fetch("id"), update
    end
  end

  def github_api(*args, input: "")
    stdout, stderr, status = Open3.capture3("gh", "api", *args, stdin_data: input)
    raise "GitHub Release API 调用失败：#{stderr.strip}" unless status.success?

    stdout
  end
end

if __FILE__ == $PROGRAM_NAME
  endpoint = "repos/#{ENV.fetch('GITHUB_REPOSITORY')}/releases"
  pages = SupersededReleases.github_api("--paginate", "--slurp", "#{endpoint}?per_page=100")
  SupersededReleases.each_update(JSON.parse(pages).flatten(1), ENV.fetch("RELEASE_VERSION")) do |id, update|
    SupersededReleases.github_api("--method", "PATCH", "#{endpoint}/#{id}", "--input", "-", input: JSON.generate(update))
    puts update.fetch("name")
  end
end

# frozen_string_literal: true

require "minitest/autorun"
require_relative "supersede-ios-releases"

class SupersededReleasesTest < Minitest::Test
  def release(build, version: "1.5.0", draft: false)
    tag = "ios/v#{version}-build.#{build}"
    {
      "id" => build, "name" => "iOS v#{version} (#{build})", "body" => "原始说明\n",
      "tag_name" => tag, "html_url" => "https://example.org/releases/tag/#{tag}",
      "draft" => draft,
      "assets" => %w[nodeseek.ipa build-provenance.json nodeseek.app.dSYM.zip].map do |name|
        { "name" => name, "state" => "uploaded" }
      end
    }
  end

  def updates(releases)
    SupersededReleases.enum_for(:each_update, releases, "1.5.0").to_h
  end

  def test_repeated_runs_link_directly_to_latest_complete_build
    old = release(2)
    current = release(10)
    releases = [release(12, draft: true), release(3, version: "1.5.01"), old, current]
    assert_equal [2], updates(releases).keys
    old.merge!(updates(releases).fetch(2))
    assert_equal "【已被新版替代】iOS v1.5.0 (2)", old.fetch("name")
    assert_includes old.fetch("body"), current.fetch("html_url")
    assert_empty updates(releases)

    latest = release(11)
    releases.unshift(latest)
    changes = updates(releases)
    assert_equal [2, 10], changes.keys.sort
    body = changes.fetch(2).fetch("body")
    assert_includes body, latest.fetch("html_url")
    refute_includes body, current.fetch("html_url")
    assert body.end_with?("\n\n原始说明\n")
    assert_equal 1, body.scan(SupersededReleases::MARKER).length
  end

  def test_incomplete_new_build_does_not_supersede_previous_download
    incomplete = release(11)
    incomplete.fetch("assets").last["state"] = "starter"
    assert_empty updates([incomplete, release(10)])
  end
end

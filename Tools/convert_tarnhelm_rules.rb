#!/usr/bin/env ruby
# frozen_string_literal: true

# Converts every encoded rule link in TarnhelmDocument's rules.md into one
# importable Nothung configuration document. The generated rule pack remains
# GPL-3.0-only; see the pack's README and LICENSE.

require "base64"
require "digest"
require "json"
require "uri"

abort "usage: convert_tarnhelm_rules.rb INPUT_RULES_MD OUTPUT_JSON MANIFEST_JSON UPSTREAM_COMMIT" unless ARGV.length == 4

input_path, output_path, manifest_path, upstream_commit = ARGV
source_text = File.read(input_path, encoding: "UTF-8")
links = source_text.scan(%r{tarnhelm://rule\?([^\)]+)}).flatten
abort "no Tarnhelm rule links found" if links.empty?

def stable_uuid(kind, index, payload)
  bytes = Digest::SHA256.digest([kind, index, payload].join("\0")).bytes.first(16)
  bytes[6] = (bytes[6] & 0x0f) | 0x50
  bytes[8] = (bytes[8] & 0x3f) | 0x80
  hex = bytes.pack("C*").unpack1("H*")
  [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join("-").upcase
end

def source_note(rule, commit)
  author = rule["d"].to_s.strip
  parts = ["TarnhelmDocument"]
  parts << "作者：#{author}" unless author.empty?
  parts << "GPL-3.0-only"
  parts << "commit #{commit}"
  parts.join(" · ")
end

parameter_rules = []
regex_rules = []
redirect_rules = []
warnings = []

links.each_with_index do |raw_query, index|
  query_type, encoded = URI.decode_www_form(raw_query).first
  begin
    decoded = Base64.strict_decode64(encoded)
    rule = JSON.parse(decoded)
  rescue StandardError => error
    abort "rule #{index + 1} could not be decoded: #{error.message}"
  end

  title = rule["a"].to_s.strip
  title = "Tarnhelm rule #{index + 1}" if title.empty?
  note = source_note(rule, upstream_commit)

  # Classify by payload fields because two historical links use a mismatched
  # query key even though their encoded records are valid regex rules.
  if rule.key?("e") && rule.key?("f")
    names = Array(rule["g"]).map(&:to_s).map(&:strip).reject(&:empty?)
    parameter_rules << {
      "id" => stable_uuid("parameter", index, decoded),
      "title" => title,
      "host" => rule["e"].to_s,
      "includesSubdomains" => false,
      "mode" => rule["f"].to_i.zero? ? "allowList" : "blockList",
      "parameterNames" => names,
      "isEnabled" => true,
      "source" => note
    }
  elsif rule.key?("b") && rule.key?("c")
    patterns = Array(rule["b"]).map(&:to_s)
    replacements = Array(rule["c"]).map(&:to_s)
    if replacements.length < patterns.length
      missing_count = patterns.length - replacements.length
      replacements.concat(Array.new(missing_count, ""))
      warnings << "link #{index + 1} (#{title}) had #{missing_count} missing replacement line(s); converted them to empty replacements"
    elsif replacements.length > patterns.length
      abort "regex rule #{index + 1} has more replacements than patterns"
    end
    regex_rules << {
      "id" => stable_uuid("regex", index, decoded),
      "title" => title,
      "patterns" => patterns,
      "replacements" => replacements,
      "caseInsensitive" => false,
      "isEnabled" => true,
      "source" => note
    }
    warnings << "link #{index + 1} (#{title}) was labelled #{query_type} but converted by its regex payload" unless query_type == "regex"
  elsif rule.key?("e")
    redirect_rules << {
      "id" => stable_uuid("redirect", index, decoded),
      "title" => title,
      "host" => rule["e"].to_s,
      "includesSubdomains" => false,
      "isEnabled" => true,
      "source" => note
    }
  else
    abort "rule #{index + 1} has an unsupported payload"
  end
end

configuration = {
  "schemaVersion" => 1,
  "useBuiltInTrackingRules" => true,
  "cleanImmediatelyAfterPaste" => false,
  "copyAfterCleaning" => false,
  "restrictRedirectExpansionToRules" => false,
  "parameterRules" => parameter_rules,
  "regexRules" => regex_rules,
  "redirectRules" => redirect_rules
}

json = JSON.pretty_generate(configuration) + "\n"
File.write(output_path, json)

manifest = {
  "name" => "Tarnhelm complete rules for Nothung",
  "license" => "GPL-3.0-only",
  "upstream" => "https://github.com/lz233/TarnhelmDocument",
  "upstreamCommit" => upstream_commit,
  "sourceFile" => "SOURCE-rules.md",
  "generatedFile" => File.basename(output_path),
  "generatedSHA256" => Digest::SHA256.hexdigest(json),
  "counts" => {
    "parameterRules" => parameter_rules.length,
    "regexRules" => regex_rules.length,
    "regexSteps" => regex_rules.sum { |rule| rule["patterns"].length },
    "redirectRules" => redirect_rules.length
  },
  "conversionWarnings" => warnings
}
File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")

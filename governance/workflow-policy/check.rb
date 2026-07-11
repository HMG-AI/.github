#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "optparse"
require "psych"

module WorkflowPolicy
  MAX_WORKFLOW_BYTES = 256 * 1024
  MAX_WORKFLOW_FILES = 256
  WORKFLOW_PATH = %r{\A\.github/workflows/[^/]+\.ya?ml\z}i
  FULL_SHA = /\A[0-9a-f]{40}\z/
  PR_LIKE_EVENTS = %w[
    pull_request
    merge_group
    pull_request_review
    pull_request_review_comment
  ].freeze
  UNTRUSTED_EXPRESSION = %r{
    (?:^|[^A-Za-z0-9_])
    (?:
      inputs(?![A-Za-z0-9_])
      |github\s*(?:
        \.\s*(?:event|head_ref|ref_name|ref)(?![A-Za-z0-9_])
        |\[\s*["'](?:event|head_ref|ref_name|ref)["']\s*\]
      )
    )
  }ix

  Violation = Struct.new(:path, :line, :code, :message, keyword_init: true)

  class Error < StandardError; end

  class Checker
    attr_reader :violations, :checked

    def initialize(repository:, scope:, base: nil, head: nil, stdout: $stdout)
      @repository = File.realpath(repository)
      @scope = scope
      @base = base
      @head = head
      @stdout = stdout
      @violations = []
      @checked = 0
    rescue Errno::ENOENT => e
      raise Error, "repository is unavailable: #{e.message}"
    end

    def run
      paths = workflow_paths
      raise Error, "refusing to inspect more than #{MAX_WORKFLOW_FILES} workflow files" if paths.length > MAX_WORKFLOW_FILES

      paths.sort.each { |path| check_file(path) }
      print_report
      violations.empty?
    end

    private

    def workflow_paths
      case @scope
      when "changed"
        validate_sha!("base", @base)
        validate_sha!("head", @head)
        ensure_commit!(@base)
        ensure_commit!(@head)
        @treeish = @head
        changed_workflow_paths
      when "repository"
        @treeish = git_capture("rev-parse", "HEAD").strip
        repository_workflow_paths
      else
        raise Error, "unsupported scope #{@scope.inspect}"
      end
    end

    def validate_sha!(label, value)
      raise Error, "#{label} SHA must be an exact lowercase 40-character commit SHA" unless FULL_SHA.match?(value.to_s)
    end

    def ensure_commit!(sha)
      _out, _err, status = Open3.capture3("git", "-C", @repository, "cat-file", "-e", "#{sha}^{commit}")
      raise Error, "commit #{sha} is unavailable" unless status.success?
    end

    def git_capture(*args)
      out, err, status = Open3.capture3("git", "-C", @repository, *args)
      raise Error, "git #{args.first} failed: #{err.strip}" unless status.success?

      out
    end

    def changed_workflow_paths
      output = git_capture(
        "diff", "--name-status", "-z", "--find-renames", "--find-copies",
        "--diff-filter=ACMRT", "#{@base}...#{@head}", "--", ".github/workflows"
      )
      fields = output.split("\0", -1)
      fields.pop if fields.last == ""
      paths = []

      until fields.empty?
        status = fields.shift
        raise Error, "malformed git diff name-status output" if status.nil? || status.empty?

        if status.start_with?("R", "C")
          raise Error, "malformed rename/copy record" if fields.length < 2

          fields.shift
          destination = fields.shift
          paths << destination if workflow_candidate_path?(destination)
        else
          raise Error, "malformed change record" if fields.empty?

          path = fields.shift
          paths << path if workflow_candidate_path?(path)
        end
      end

      paths.uniq
    end

    def repository_workflow_paths
      output = git_capture("ls-files", "-z", "--", ".github/workflows")
      output.split("\0").select { |path| workflow_candidate_path?(path) }.uniq
    end

    def workflow_candidate_path?(path)
      return false unless path.is_a?(String)

      prefix = ".github/workflows/".b
      bytes = path.b
      return false unless bytes.start_with?(prefix)

      filename = bytes.delete_prefix(prefix)
      suffix_matches = filename.downcase.end_with?(".yml".b, ".yaml".b)
      !filename.empty? && !filename.include?("/".b) && suffix_matches
    end

    def workflow_path?(path)
      path.is_a?(String) && path.valid_encoding? && !path.match?(/[[:cntrl:]]/) && WORKFLOW_PATH.match?(path)
    end

    def check_file(relative)
      @location_offsets = {}
      unless workflow_path?(relative)
        add(relative.to_s, 1, "path.invalid", "workflow path is outside the active root workflow directory")
        return
      end

      absolute = File.expand_path(relative, @repository)
      unless absolute.start_with?("#{@repository}/")
        add(relative, 1, "path.escape", "workflow path escapes the repository")
        return
      end

      stat = File.lstat(absolute)
      unless stat.file? && !stat.symlink?
        add(relative, 1, "file.non_regular", "workflow must be a regular, non-symlink file")
        return
      end
      unless head_blob_matches?(relative, absolute)
        add(relative, 1, "file.head_mismatch", "workflow bytes must match the exact checked-out event head")
        return
      end
      if stat.size > MAX_WORKFLOW_BYTES
        add(relative, 1, "file.oversized", "workflow exceeds #{MAX_WORKFLOW_BYTES} bytes")
        return
      end

      content = File.binread(absolute)
      unless content.force_encoding(Encoding::UTF_8).valid_encoding?
        add(relative, 1, "yaml.encoding", "workflow is not valid UTF-8")
        return
      end

      @checked += 1
      document = parse_yaml(relative, content)
      check_document(relative, content, document) if document
    rescue Errno::ENOENT
      add(relative, 1, "file.missing", "changed workflow is missing from the checked-out head")
    rescue SystemCallError => e
      add(relative, 1, "file.read", "workflow could not be read: #{e.message}")
    end

    def head_blob_matches?(relative, absolute)
      tree_entry = git_capture("ls-tree", "-z", @treeish, "--", relative).delete_suffix("\0")
      metadata, entry_path = tree_entry.split("\t", 2)
      return false unless entry_path == relative

      mode, type, expected_object = metadata.to_s.split(" ", 3)
      return false unless %w[100644 100755].include?(mode) && type == "blob"

      actual_object = git_capture("hash-object", "--", absolute).strip
      actual_object == expected_object
    rescue Error
      false
    end

    def parse_yaml(path, content)
      stream = Psych.parse_stream(content, filename: path)
      unless stream.children.length == 1
        add(path, 1, "yaml.document_count", "workflow must contain exactly one YAML document")
        return nil
      end

      document_node = stream.children.first
      reject_unsafe_nodes(path, document_node)
      return nil if violations.any? { |item| item.path == path && item.code.start_with?("yaml.") }

      value = Psych.safe_load(
        content,
        permitted_classes: [],
        permitted_symbols: [],
        aliases: false,
        filename: path
      )
      unless value.is_a?(Hash)
        add(path, 1, "yaml.root", "workflow root must be a mapping")
        return nil
      end

      value
    rescue Psych::Exception => e
      line = e.respond_to?(:line) && e.line ? e.line : 1
      add(path, line, "yaml.parse", "workflow YAML is unsafe or invalid: #{e.message.lines.first.to_s.strip}")
      nil
    end

    def reject_unsafe_nodes(path, node)
      if node.is_a?(Psych::Nodes::Alias)
        add(path, node.start_line + 1, "yaml.alias", "YAML aliases are not allowed")
        return
      end

      if node.is_a?(Psych::Nodes::Mapping)
        seen = {}
        semantic_seen = {}
        node.children.each_slice(2) do |key, _value|
          unless key.is_a?(Psych::Nodes::Scalar)
            add(path, key.start_line + 1, "yaml.complex_key", "mapping keys must be plain scalars")
            next
          end
          if seen.key?(key.value)
            add(path, key.start_line + 1, "yaml.duplicate_key", "duplicate mapping key #{key.value.inspect}")
          else
            seen[key.value] = true
          end

          semantic_key = yaml_semantic_key(key)
          if semantic_seen.key?(semantic_key) && semantic_seen[semantic_key] != key.value
            add(path, key.start_line + 1, "yaml.duplicate_key", "mapping keys #{semantic_seen[semantic_key].inspect} and #{key.value.inspect} have the same YAML meaning")
          else
            semantic_seen[semantic_key] = key.value
          end
        end
      end

      Array(node.respond_to?(:children) ? node.children : nil).each do |child|
        reject_unsafe_nodes(path, child)
      end
    end

    def yaml_semantic_key(node)
      return [String.name, node.value] unless node.respond_to?(:plain) && node.plain

      value = Psych.safe_load(
        node.value,
        permitted_classes: [],
        permitted_symbols: [],
        aliases: false
      )
      [value.class.name, value]
    rescue Psych::Exception
      [String.name, node.value]
    end

    def check_document(path, content, document)
      triggers = document.key?("on") ? document["on"] : document[true]
      events = event_names(triggers)
      if events.empty?
        add(path, locate(content, "on:"), "trigger.missing", "workflow must declare at least one event trigger")
      end
      if events.include?("pull_request_target")
        add(path, locate(content, "pull_request_target"), "trigger.pull_request_target", "pull_request_target is forbidden")
      end

      permissions = document["permissions"]
      if permissions.nil?
        add(path, 1, "permissions.missing", "top-level permissions must be explicit")
      else
        check_permissions(path, content, permissions, "top-level", events)
      end

      jobs = document["jobs"]
      unless jobs.is_a?(Hash) && !jobs.empty?
        add(path, locate(content, "jobs:"), "jobs.invalid", "jobs must be a non-empty mapping")
        return
      end

      jobs.each do |job_id, job|
        unless job_id.is_a?(String) && job.is_a?(Hash)
          add(path, locate(content, job_id.to_s), "job.invalid", "each job must be a mapping with a string identifier")
          next
        end
        check_runner(path, content, job["runs-on"], events, job_id) if job.key?("runs-on")
        check_permissions(path, content, job["permissions"], "job #{job_id}", events) if job.key?("permissions")
        check_uses(path, content, job["uses"], "job #{job_id}") if job.key?("uses")
        check_container(path, content, job["container"], "job #{job_id} container") if job.key?("container")
        check_services(path, content, job["services"], job_id) if job.key?("services")

        steps = job["steps"]
        next if steps.nil?
        unless steps.is_a?(Array)
          add(path, locate(content, "steps:"), "steps.invalid", "steps for job #{job_id} must be a sequence")
          next
        end

        steps.each_with_index do |step, index|
          unless step.is_a?(Hash)
            add(path, locate(content, "steps:"), "step.invalid", "step #{index + 1} in job #{job_id} must be a mapping")
            next
          end
          label = "job #{job_id} step #{index + 1}"
          uses = step["uses"]
          check_uses(path, content, uses, label) if uses
          check_checkout(path, content, step, events, label) if checkout_use?(uses)
          check_executable(path, content, step["run"], "#{label} run") if step.key?("run")
          if github_script_use?(uses)
            with = step["with"]
            script = with.is_a?(Hash) ? with["script"] : nil
            check_executable(path, content, script, "#{label} github-script") if script
          end
        end
      end
    end

    def event_names(value)
      names = case value
              when String then [value]
              when Array then value
              when Hash then value.keys
              else []
              end
      names.select { |name| name.is_a?(String) }.map(&:downcase).uniq
    end

    def check_permissions(path, content, value, label, events)
      if value == "write-all"
        add(path, locate(content, "write-all"), "permissions.write_all", "#{label} permissions must not use write-all")
        return
      end
      return if value == "read-all"

      unless value.is_a?(Hash)
        add(path, locate(content, "permissions:"), "permissions.invalid", "#{label} permissions must be read-all or a mapping")
        return
      end

      invalid = value.reject do |scope, access|
        scope.is_a?(String) && %w[read write none].include?(access.to_s)
      end
      unless invalid.empty?
        add(path, locate(content, "permissions:"), "permissions.invalid", "#{label} permissions contain an invalid scope or access level")
        return
      end

      writes = value.select { |_scope, access| access.to_s == "write" }.keys
      return if writes.empty? || (events & PR_LIKE_EVENTS).empty?

      add(
        path,
        locate(content, "write"),
        "permissions.pr_write",
        "#{label} grants write permission on a pull-request, merge-group, or review event: #{writes.join(', ')}"
      )
    end

    def check_runner(path, content, value, events, job_id)
      return if (events & PR_LIKE_EVENTS).empty?

      if contains_self_hosted?(value)
        add(
          path,
          locate(content, "self-hosted"),
          "runner.pr_self_hosted",
          "job #{job_id} must not run an untrusted event on a self-hosted runner"
        )
      end

      expression = first_untrusted_expression(value)
      return unless expression

      add(
        path,
        locate(content, "${{#{expression}}}"),
        "runner.pr_untrusted_expression",
        "job #{job_id} must not select its runner from an untrusted event or input context"
      )
    end

    def contains_self_hosted?(value)
      case value
      when String
        value.downcase.split(/[^a-z0-9_-]+/).include?("self-hosted")
      when Array
        value.any? { |item| contains_self_hosted?(item) }
      when Hash
        value.values.any? { |item| contains_self_hosted?(item) }
      else
        false
      end
    end

    def first_untrusted_expression(value)
      case value
      when String
        value.scan(/\$\{\{(.*?)\}\}/m).map(&:first).find { |expression| UNTRUSTED_EXPRESSION.match?(expression) }
      when Array
        value.filter_map { |item| first_untrusted_expression(item) }.first
      when Hash
        value.values.filter_map { |item| first_untrusted_expression(item) }.first
      end
    end

    def check_container(path, content, value, label)
      image = value.is_a?(Hash) ? value["image"] : value
      unless image.is_a?(String) && container_digest?(image)
        add(path, locate(content, image || "container:"), "container.unpinned", "#{label} image must be pinned by a lowercase sha256 digest")
      end
    end

    def check_services(path, content, value, job_id)
      unless value.is_a?(Hash)
        add(path, locate(content, "services:"), "services.invalid", "services for job #{job_id} must be a mapping")
        return
      end

      value.each do |service_id, service|
        image = service.is_a?(Hash) ? service["image"] : nil
        unless image.is_a?(String) && container_digest?(image)
          add(
            path,
            locate(content, image || service_id.to_s),
            "container.unpinned",
            "job #{job_id} service #{service_id} image must be pinned by a lowercase sha256 digest"
          )
        end
      end
    end

    def container_digest?(image)
      %r{\A[^\s@]+@sha256:[0-9a-f]{64}\z}.match?(image)
    end

    def check_uses(path, content, value, label)
      unless value.is_a?(String)
        add(path, locate(content, "uses:"), "uses.invalid", "#{label} uses must be a literal string")
        return
      end
      return if value.start_with?("./")

      if value.start_with?("docker://")
        unless container_digest?(value.delete_prefix("docker://"))
          add(path, locate(content, value), "uses.docker_unpinned", "#{label} Docker use must be pinned by a lowercase sha256 digest")
        end
        return
      end

      unless %r{\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.\-/]+)?@[0-9a-f]{40}\z}.match?(value)
        add(path, locate(content, value), "uses.unpinned", "#{label} external use must be pinned to a lowercase 40-character commit SHA")
      end
    end

    def checkout_use?(value)
      value.is_a?(String) && value.match?(%r{\Aactions/checkout@}i)
    end

    def github_script_use?(value)
      value.is_a?(String) && value.match?(%r{\Aactions/github-script@}i)
    end

    def check_checkout(path, content, step, events, label)
      with = step["with"]
      persist = with.is_a?(Hash) ? with["persist-credentials"] : nil
      unless persist == false || persist.to_s.downcase == "false"
        add(path, locate(content, "actions/checkout@"), "checkout.persist_credentials", "#{label} must set persist-credentials: false")
      end

      return if (events & PR_LIKE_EVENTS).empty? || !with.is_a?(Hash)

      %w[token ssh-key].each do |key|
        next unless with.key?(key)

        add(path, locate(content, "#{key}:"), "checkout.pr_credential", "#{label} must not override checkout #{key} on an untrusted event")
      end
    end

    def check_executable(path, content, value, label)
      unless value.is_a?(String)
        add(path, locate(content, "run:"), "script.invalid", "#{label} must be a string")
        return
      end

      expression = first_untrusted_expression(value)
      if expression
        add(path, locate(content, "${{#{expression}}}"), "script.untrusted_expression", "#{label} directly interpolates an untrusted event or input context")
      end

      if direct_main_push?(value)
        add(path, locate(content, "git push"), "script.direct_main_push", "#{label} appears to push directly to main/master")
      end
      if direct_main_api_write?(value)
        add(path, locate(content, "refs/heads/"), "script.direct_main_api", "#{label} appears to mutate main/master through the refs API")
      end
    end

    def direct_main_push?(script)
      logical_shell_lines(script).any? do |line|
        line.match?(%r{\bgit\s+(?:-[^\s]+\s+)*push\b[^\n;&|]*(?:refs/heads/(?:main|master)\b|\b(?:main|master)\b)}i)
      end
    end

    def direct_main_api_write?(script)
      normalized = script.gsub(/\\\r?\n/, " ").gsub(/\s+/, " ")
      main_ref = normalized.match?(%r{(?:git/)?refs?(?:/heads/|=refs/heads/)(?:main|master)\b}i)
      return false unless main_ref

      gh_write = normalized.match?(%r{\bgh\s+api\b}i) &&
        normalized.match?(%r{(?:-X|--method)\s*(?:POST|PUT|PATCH|DELETE)\b|(?:^|\s)(?:-f|-F|--field|--raw-field|--input)(?:\s|=)}i)
      curl_write = normalized.match?(%r{\bcurl\b}i) &&
        normalized.match?(%r{(?:-X|--request)\s*(?:POST|PUT|PATCH|DELETE)\b}i)
      octokit_write = normalized.match?(%r{\b(?:github|octokit)\.rest\.git\.(?:createRef|updateRef|deleteRef)\s*\(}i) ||
        normalized.match?(%r{\b(?:github|octokit)\.request\s*\(\s*["'](?:POST|PUT|PATCH|DELETE)\s+[^"']*/git/refs}i)
      gh_write || curl_write || octokit_write
    end

    def logical_shell_lines(script)
      script.gsub(/\\\r?\n/, " ").lines
    end

    def locate(content, needle)
      key = needle.to_s
      matches = []
      content.lines.each_with_index { |line, index| matches << index + 1 if line.include?(key) }
      return 1 if matches.empty?

      offset = @location_offsets.fetch(key, 0)
      @location_offsets[key] = offset + 1
      matches.fetch([offset, matches.length - 1].min)
    end

    def add(path, line, code, message)
      safe_path = path.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "?")
      violations << Violation.new(path: safe_path, line: [line.to_i, 1].max, code: code, message: message)
    end

    def print_report
      violations.sort_by { |item| [item.path, item.line, item.code] }.each do |item|
        path = workflow_command_escape(item.path, property: true)
        code = workflow_command_escape(item.code, property: true)
        message = workflow_command_escape(item.message)
        @stdout.puts("::error file=#{path},line=#{item.line},title=#{code}::#{message}")
      end
      categories = violations.group_by(&:code).transform_values(&:length).sort.to_h
      @stdout.puts("workflow-policy: checked=#{checked} violations=#{violations.length} categories=#{categories}")
    end

    def workflow_command_escape(value, property: false)
      escaped = value.to_s.gsub("%", "%25").gsub("\r", "%0D").gsub("\n", "%0A")
      property ? escaped.gsub(":", "%3A").gsub(",", "%2C") : escaped
    end
  end
end

options = { scope: "changed" }
parser = OptionParser.new do |opts|
  opts.banner = "Usage: check.rb --repository PATH [--scope changed --base SHA --head SHA]"
  opts.on("--repository PATH") { |value| options[:repository] = value }
  opts.on("--scope SCOPE", %w[changed repository]) { |value| options[:scope] = value }
  opts.on("--base SHA") { |value| options[:base] = value }
  opts.on("--head SHA") { |value| options[:head] = value }
end

begin
  parser.parse!
  raise OptionParser::MissingArgument, "--repository" unless options[:repository]

  checker = WorkflowPolicy::Checker.new(**options)
  exit(checker.run ? 0 : 1)
rescue OptionParser::ParseError, WorkflowPolicy::Error => e
  warn("workflow-policy: fatal: #{e.message}")
  exit(2)
rescue StandardError => e
  warn("workflow-policy: fatal: #{e.class}: #{e.message}")
  exit(2)
end

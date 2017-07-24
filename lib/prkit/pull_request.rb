require 'git'
require 'octokit'

module Prkit
  class PullRequestException < RuntimeError
  end

  class PullRequest
    attr_reader :commit_message

    def initialize(dir: Dir.pwd, options: {})
      @dir = dir
      @options = options
      @master = options[:master] || 'master'
      @branch_name = options[:branch] || 'prkit'
      @remote = options[:remote] || 'origin'
      @fork_to_remote = options[:fork_to_remote] || 'origin'
      @title = options[:title]
      @commit_message = options[:commit_message] || 'Automated commit by PRKit'
    end

    def execute
      Dir.chdir(@dir) do
        @git = Git.open(@dir)
        abort_if_not_clean
        prep_branch
        yield if block_given?
        commit_branch_and_pr
      end
    end

    private

    def abort_if_not_clean
      status = @git.status
      raise PullRequestException.new('Directory does not have clean git status') unless status.clean?
    end

    def prep_branch
      fork_and_add_remote
      # Very important to prune fetch the remote in case the remote branch has been deleted
      prune_remote_branches
      @git.branch(@master).checkout # ensure checkout master
      puts "Pulling latest #{File.basename(Dir.pwd)} code..."
      @git.pull

      existing_pr = existing_pull_request
      existing_remote = @git.branches.detect { |b| b.name == branch.name && !b.remote.nil? && b.remote.name == branch.fork_to_remote }

      if !existing_pr && existing_remote
        puts "No existing PR, removing remote branch #{branch.fork_to_remote}/#{branch.name}"
        puts @git.push(branch.fork_to_remote, ":#{branch.name}")
        prune_remote_branches
        existing_remote = nil
      end

      existing_local = @git.branches.detect { |b| b.name == branch.name && b.remote.nil? }

      # this can happen if we've had to manually close out a PR and
      # delete a branch that had glitches in it or other reasons.
      if !existing_pr && existing_local
        puts "No existing PR, removing local branch #{branch.name}"
        puts @git.branch(branch.name).delete
        existing_local = nil
      end

      if existing_remote && !existing_local
        puts 'Making tracking branch'
        puts @git.lib.send(:command, 'checkout', ['-t', "#{branch.fork_to_remote}/#{branch.name}"])
      else
        puts @git.branch(branch.name).checkout
      end

      @git.pull(branch.fork_to_remote, branch.name) if existing_remote
    end

    def prune_remote_branches
      @git.fetch(branch.fork_to_remote, prune: true)
    end

    def commit_branch_and_pr
      # this is odd, but led by real world experience. In some cases, content updates that cause
      # a whitespace-only change will indicate as dirty BEFORE a git add, but then after git add,
      # git apparently removes the change, so we should do the clean check AFTER the add.
      @git.add(all: true)
      if @git.status.clean?
        puts 'No changes to commit'
        @git.branch(@master).checkout
        return
      end
      @git.commit_all(@commit_message)
      push_branch_to_remote
      create_pull_request
    end

    def push_branch_to_remote
      puts "Pushing #{branch.fork_to_remote}/#{branch.name}..."

      fork_and_add_remote
      @git.push(branch.fork_to_remote, branch.name)
    end


    def fork_and_add_remote
      return unless branch.needs_fork?
      fork_data = github_client.fork(authoritative_repo(branch.fork_to_remote))
      @git.add_remote(branch.fork_to_remote, fork_data.ssh_url)
    rescue Git::GitExecuteError => e
      raise unless e.message =~ /remote.*already.*exists/
    end

    def create_pull_request
      existing = existing_pull_request
      unless existing
        pr = github_client.create_pull_request(authoritative_repo(branch.remote), @master, "#{branch.fork_to_remote}:#{branch.name}", branch.title)
        puts "Created PR ##{pr[:number]}"
      end
    end

    def existing_pull_request
      github_client.pulls(authoritative_repo(branch.remote), state: 'open').detect { |pull| pull[:title] == branch.title }
    end

    def authoritative_repo(remote_to_use)
      # returns a value formatted as org/repo, e.g.,
      #
      # "livingsocial/crispy-duck"
      #
      @git.config["remote.#{remote_to_use}.url"].split(':').last.sub(/\.git\z/, '')
    end

    def github_client
      @github_client ||= GitHubClient.new
    end

    def branch
      @branch ||= Branch.new(@branch_name, @title, @remote, @fork_to_remote)
    end
  end

  class GitHubClient
    attr_reader :client

    def initialize(api_endpoint: nil, access_token: ENV['PRKIT_GITHUB_ACCESS_TOKEN'])
      Octokit.configure do |c|
        c.api_endpoint = api_endpoint unless api_endpoint.nil?
      end
      @client = ::Octokit::Client.new(access_token: access_token)
      @client.user.login
    end

    def method_missing(meth_id, *args, &block)
      @client.send(meth_id, *args, &block)
    end
  end

  class Branch
    attr_reader :name, :title, :remote, :fork_to_remote

    def initialize(name, title, remote, fork_to_remote)
      @name = name
      @title = title || 'PRKit Pull Request'
      @remote = remote
      @fork_to_remote = fork_to_remote
    end

    def needs_fork?
      @remote != @fork_to_remote
    end
  end
end

module Git
  class Status
    def clean?
      tracked_dirty.empty?
    end

    def tracked_dirty
      (changed.values + added.values + deleted.values)
    end

    def short
      tracked_dirty.map { |f| "#{File.join(@base.dir.path, f.path)}: #{f.type}" }
    end
  end
end

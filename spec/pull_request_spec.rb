require_relative 'spec_helper'

describe Prkit::PullRequest do
  before do
    setup_temp_dir
  end

  def setup_temp_dir
    @dir = File.join(Dir.tmpdir, 'prkit-test')

    FileUtils.remove_entry_secure(@dir) if File.exist?(@dir)

    @work = File.join(@dir, 'work')
    FileUtils.makedirs @work

    @gw = Git.clone('git@github.com:livingsocial/crispy-duck.git', 'crispy-duck', path: @work)
    @work = File.join(@work, 'crispy-duck')

    @gh = Prkit::GitHubClient.new

    # fork and add the chrismo remote
    # TODO: de-dup as this is duped in Patcher guts
    authoritative_repo = @gw.config['remote.origin.url'].split(':').last.sub(/\.git\z/, '')
    fork_data = @gh.fork(authoritative_repo)
    @gw.add_remote("chrismo", fork_data.ssh_url)

    @gh.pulls('livingsocial/crispy-duck', state: 'open').each do |pull|
      @gh.close_pull_request('livingsocial/crispy-duck', pull[:number])
    end
  end

  after do
    FileUtils.remove_entry_secure(@dir) unless @do_not_clean
    # clean up the branches on remotes
  end

  def add_file(name, contents)
    File.open(File.join(@work, name), 'w') { |f| f.print contents }
    @gw.add(all: true)
  end

  def default_branch_name
    'prkit'
  end

  def ding_a_change
    File.open(File.join(@work, '.ruby-version'), 'w') { |f| f.puts '2.3.4' }
  end

  it 'should abort on not a clean dir' do
    add_file('foo.txt', 'this is foo')

    expect { Prkit::PullRequest.new(dir: @work).execute }.to raise_error Prkit::PullRequestException
  end

  it 'should do nothing if nothing to update' do
    ############################################################################
    # first, we need an existing PR (which these tests always ensure is closed).
    ############################################################################
    other_master = 'doin_nothin'
    Prkit::PullRequest.new(dir: @work, options: {master: other_master, fork_to_remote: 'chrismo'}).execute { ding_a_change }
    expect(@gw.status.clean?).to eql true
    expect(@gw.lib.branch_current).to eql default_branch_name

    ###################################
    # now, re-run and it should be fine
    ###################################
    @gw.checkout(other_master)

    Prkit::PullRequest.new(dir: @work, options: {master: other_master, fork_to_remote: 'chrismo'}).execute
    expect(@gw.status.clean?).to eql true
    expect(@gw.lib.branch_current).to eql other_master

    # this message should stay as the HEAD commit on master
    expect(@gw.log.first.message).to eql 'Update README.md'
  end

  it 'should patch away, push branch and make PR' do
    expect(@gh.pulls('livingsocial/crispy-duck', state: 'open').length).to eql 0

    # make sure remote branch is deleted
    puts @gw.lib.send(:command, 'push', ['origin', ":#{default_branch_name}"]) rescue nil

    patcher = Prkit::PullRequest.new(dir: @work, options: {fork_to_remote: 'chrismo'})
    patcher.execute { ding_a_change }

    expect(@gw.status.clean?).to eql true
    expect(@gw.lib.branch_current).to eql default_branch_name
    expect(@gw.log.first.message.chomp).to eql patcher.send(:commit_message).chomp

    # brittle test - but hey ... for now.
    expect(File.read(File.join(@work, '.ruby-version')).chomp).to eql '2.3.4'

    pulls = @gh.pulls('livingsocial/crispy-duck', state: 'open')
    expect(pulls.length).to eql 1

    ####
    # Now do it again with minor preferred and make sure the PR creation is idempotent
    ####

    Prkit::PullRequest.new(dir: @work, options: {fork_to_remote: 'chrismo'}).execute do
      File.open(File.join(@work, '.ruby-version'), 'w') { |f| f.puts '2.3.5' }
    end

    pulls = @gh.pulls('livingsocial/crispy-duck', state: 'open')
    expect(pulls.length).to eql 1

    ####
    # Now, remove the remote branch and PR and try again to make sure this case gets handled
    ####

    # Hmm, I can't delete the remote branch using `git push origin :branch` because that also
    # clears out the remote reference to it locally, which won't exercise the recent fix to
    # ensure a git fetch chrismo --prune is done. So ... no test for this :/

    @gh.close_pull_request('livingsocial/crispy-duck', pulls.first[:number])
  end

  describe Prkit::Branch do
    it 'should generate name from title'
  end

  # it 'should report an existing branch if recreate not passed'
  # ... but these are expensive tests to run ... so I'm conflicted. low risk of not detecting breakage in advance.

  # it 'should avoid repeat attempt fu by re-using same branch name only if does not exist'
  # or just re-use it? we should be able to re-run stuff to update a PR, esp. while we're tuning all this

end

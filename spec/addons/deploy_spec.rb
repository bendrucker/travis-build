require 'spec_helper'

describe Travis::Build::Script::Addons::Deploy, :sexp do
  let(:scripts) { { before_deploy: ['./before_deploy_1.sh', './before_deploy_2.sh'], after_deploy: ['./after_deploy_1.sh', './after_deploy_2.sh'] } }
  let(:config)  { {} }
  let(:data)    { PAYLOADS[:push].deep_clone }
  let(:sh)      { Travis::Shell::Builder.new }
  let(:addon)   { described_class.new(sh, Travis::Build::Data.new(data), config) }
  subject       { addon.deploy && sh.to_sexp }

  let(:terminate_on_failure) { [:if, '$? -ne 0', [:then, [:cmds, [[:echo, 'Failed to deploy.', ansi: :red], [:cmd, 'travis_terminate 2']]]]] }

  describe 'deploys if conditions apply' do
    let(:config) { { provider: 'heroku', password: 'foo', email: 'user@host' }.merge(scripts) }
    let(:sexp)   { sexp_find(subject, [:if, '(-z $TRAVIS_PULL_REQUEST) && ($TRAVIS_BRANCH = master)']) }

    it { expect(sexp).to include_sexp [:cmd, './before_deploy_1.sh', assert: true, echo: true, timing: true] }
    it { expect(sexp).to include_sexp [:cmd, './before_deploy_2.sh', assert: true, echo: true, timing: true] }
    it { expect(sexp).to include_sexp [:cmd, 'rvm 1.9.3 --fuzzy do ruby -S gem install dpl', assert: true, timing: true] }
    it { expect(sexp).to include_sexp [:cmd, 'rvm 1.9.3 --fuzzy do ruby -S dpl --provider="heroku" --password="foo" --email="user@host" --fold', assert: true, timing: true] }
    it { expect(sexp).to include_sexp terminate_on_failure }
    it { expect(sexp).to include_sexp [:cmd, './after_deploy_1.sh', assert: true, echo: true, timing: true] }
    it { expect(sexp).to include_sexp [:cmd, './after_deploy_2.sh', assert: true, echo: true, timing: true] }
  end

  describe 'implicit branches' do
    let(:data)   { super().merge(branch: 'staging') }
    let(:config) { { provider: 'heroku', app: { staging: 'foo', production: 'bar' } } }

    it { should match_sexp [:if, '(-z $TRAVIS_PULL_REQUEST) && ($TRAVIS_BRANCH = staging || $TRAVIS_BRANCH = production)'] }
  end

  describe 'on tags' do
    let(:config) { { provider: 'heroku', on: { tags: true } } }

    it { should match_sexp [:if, '(-z $TRAVIS_PULL_REQUEST) && ($TRAVIS_BRANCH = master) && (-n $TRAVIS_TAG)'] }
  end

  describe 'multiple providers' do
    let(:heroku)    { { provider: 'heroku', password: 'foo', email: 'user@host', on: { condition: '$FOO = foo' } } }
    let(:nodejitsu) { { provider: 'nodejitsu', user: 'foo', api_key: 'bar', on: { condition: '$BAR = bar' } } }
    let(:config)    { [heroku, nodejitsu] }

    it { should match_sexp [:if, '(-z $TRAVIS_PULL_REQUEST) && ($TRAVIS_BRANCH = master) && ($FOO = foo)'] }
    it { should include_sexp [:cmd, 'rvm 1.9.3 --fuzzy do ruby -S dpl --provider="heroku" --password="foo" --email="user@host" --fold', assert: true, timing: true] }
    it { should match_sexp [:if, '(-z $TRAVIS_PULL_REQUEST) && ($TRAVIS_BRANCH = master) && ($BAR = bar)'] }
    it { should include_sexp [:cmd, 'rvm 1.9.3 --fuzzy do ruby -S dpl --provider="nodejitsu" --user="foo" --api_key="bar" --fold', assert: true, timing: true] }
  end

  describe 'allow_failure' do
    let(:config) { { provider: 'heroku', password: 'foo', email: 'user@host', allow_failure: true } }

    it { should_not include_sexp terminate_on_failure }
  end

  describe 'multiple conditions match' do
    let(:config) { { provider: 'heroku', on: { condition: ['$FOO = foo', '$BAR = bar'] } } }
    before       { addon.deploy }

    it { should match_sexp [:if, '(-z $TRAVIS_PULL_REQUEST) && ($TRAVIS_BRANCH = master) && (($FOO = foo) && ($BAR = bar))'] }
  end

  describe 'deploy condition fails' do
    let(:config) { { provider: 'heroku', on: { condition: '$ENV_2 = 1'} } }
    let(:sexp)   { sexp_find(subject, [:if, '(-z $TRAVIS_PULL_REQUEST) && ($TRAVIS_BRANCH = master) && ($ENV_2 = 1)'], [:else]) }

    let(:not_permitted)    { [:echo, 'Skipping deployment with the heroku provider because this branch is not permitted to deploy as per configuration.', ansi: :red] }
    let(:custom_condition) { [:echo, 'Skipping deployment with the heroku provider because a custom condition was not met.', ansi: :red] }
    let(:is_pull_request)  { [:echo, 'Skipping deployment with the heroku provider because the current build is a pull request.', ansi: :red] }

    it { expect(sexp_find(sexp, [:if, '(! -z $TRAVIS_PULL_REQUEST)'])).to include_sexp is_pull_request }
    it { expect(sexp_find(sexp, [:if, '(! $TRAVIS_BRANCH = master)'])).to include_sexp not_permitted }
    it { expect(sexp_find(sexp, [:if, '(! $ENV_2 = 1)'])).to include_sexp custom_condition }
  end
end


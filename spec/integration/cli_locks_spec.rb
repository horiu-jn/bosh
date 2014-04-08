require 'spec_helper'

describe 'cli: locks', type: :integration do
  with_reset_sandbox_before_each

  context 'when a deployment is in progress' do
    before do
      manifest_hash = Bosh::Spec::Deployments.simple_manifest
      manifest_hash['update']['canary_watch_time'] = 6000
      deploy_simple(manifest_hash: manifest_hash, no_track: true)
    end

    it 'lists a deployment lock' do
      output = ''

      10.times do
        # bosh locks returns exit code 1 if there are no locks
        output, exit_code = run_bosh('locks', failure_expected: true, return_exit_code: true)
        break if exit_code.zero?
        sleep(0.5)
      end

      expect(output).to match(/\s*\|\s*deployment\s*\|\s*simple\s*\|/)
    end
  end

  context 'when nothing is in progress' do
    it 'returns no locks' do
      target_and_login
      expect_output('locks', 'No locks')
    end
  end
end
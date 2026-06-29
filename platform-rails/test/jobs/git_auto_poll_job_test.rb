require "test_helper"

class GitAutoPollJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def auto_stack
    git_stacks(:auto_update_stack)  # auto_update: true, self_heal: false, last_commit_sha: "abc123"
  end

  def self_heal_stack
    git_stacks(:self_heal_stack)  # auto_update: true, self_heal: true, sync_status: out_of_sync
  end

  test "skips when stack has auto_update disabled" do
    stack = git_stacks(:basic_git_stack)
    with_stub(GitPollService, :call, "new_sha") do
      assert_no_enqueued_jobs do
        GitAutoPollJob.perform_now(stack.id)
      end
    end
  end

  test "early returns without unpack when sha unchanged and self_heal disabled" do
    unpacker_called = false
    stub_unpacker = ->(*) { unpacker_called = true; "/tmp/repo" }
    with_stub(GitPollService, :call, auto_stack.last_commit_sha) do
      with_stub(GitUnpacker, :call, stub_unpacker) do
        GitAutoPollJob.perform_now(auto_stack.id)
      end
    end
    refute unpacker_called
  end

  test "enqueues GitDeployJob when commit changed and inside sync window" do
    stack = auto_stack
    with_stub(GitPollService, :call, "brand_new_sha") do
      with_stub(GitUnpacker, :call, "/tmp/repo") do
        with_stub(GitDriftService, :call, nil) do
          assert_enqueued_with(job: GitDeployJob) do
            GitAutoPollJob.perform_now(stack.id)
          end
        end
      end
    end
  end

  test "creates alert instead of deploying when outside sync window" do
    stack = auto_stack
    stack.update!(sync_window: "mon-fri 22:00-23:00")  # always outside in test

    with_stub(GitPollService, :call, "outside_window_sha") do
      with_stub(GitUnpacker, :call, "/tmp/repo") do
        with_stub(GitDriftService, :call, nil) do
          assert_no_enqueued_jobs only: GitDeployJob do
            assert_difference "Alert.count", 1 do
              GitAutoPollJob.perform_now(stack.id)
            end
          end
        end
      end
    end
  end

  test "self_heal stack unpacks even when sha unchanged" do
    stack = self_heal_stack
    unpacker_called = false
    stub_unpacker = ->(*) { unpacker_called = true; "/tmp/repo" }

    with_stub(GitPollService, :call, stack.last_commit_sha) do
      with_stub(GitUnpacker, :call, stub_unpacker) do
        with_stub(GitDriftService, :call, nil) do
          with_stub(GitDeployJob, :perform_later, nil) do
            GitAutoPollJob.perform_now(stack.id)
          end
        end
      end
    end
    assert unpacker_called
  end

  test "self_heal stack enqueues deploy when out_of_sync" do
    stack = self_heal_stack  # sync_status: out_of_sync

    with_stub(GitPollService, :call, stack.last_commit_sha) do
      with_stub(GitUnpacker, :call, "/tmp/repo") do
        with_stub(GitDriftService, :call, nil) do
          assert_enqueued_with(job: GitDeployJob) do
            GitAutoPollJob.perform_now(stack.id)
          end
        end
      end
    end
  end
end

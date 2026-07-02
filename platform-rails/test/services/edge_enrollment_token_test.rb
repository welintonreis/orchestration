require "test_helper"

class EdgeEnrollmentTokenTest < ActiveSupport::TestCase
  test "generate then consume returns the requested node name and a uuid" do
    token = EdgeEnrollmentToken.generate(node_name: "box1")
    data = EdgeEnrollmentToken.consume(token)
    assert_equal "box1", data["name"]
    assert data["uuid"].present?
  end

  test "the embedded uuid enrolling twice collides on EdgeNode's unique index" do
    token = EdgeEnrollmentToken.generate(node_name: "box1")
    data = EdgeEnrollmentToken.consume(token)

    EdgeNode.enroll!(name: data["name"], uuid: data["uuid"])
    assert_raises(ActiveRecord::RecordInvalid) do
      EdgeNode.enroll!(name: data["name"], uuid: data["uuid"])
    end
  end

  test "a tampered token is rejected" do
    token = EdgeEnrollmentToken.generate(node_name: "box1")
    assert_nil EdgeEnrollmentToken.consume(token + "x")
  end

  test "an expired token is rejected" do
    token = travel_to(20.minutes.ago) { EdgeEnrollmentToken.generate(node_name: "box1") }
    assert_nil EdgeEnrollmentToken.consume(token)
  end

  test "garbage input never raises" do
    assert_nil EdgeEnrollmentToken.consume("not-a-real-token")
  end
end

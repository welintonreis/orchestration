require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "valid admin user" do
    user = User.new(email_address: "new@example.com", password: "secret123", role: "admin")
    assert user.valid?
  end

  test "email_address must be unique at database level" do
    existing = users(:admin_user)
    user = User.new(email_address: existing.email_address, password: "secret", role: "admin")
    assert_raises(ActiveRecord::RecordNotUnique) { user.save! }
  end

  test "normalizes email to lowercase" do
    user = User.create!(email_address: "  ADMIN2@EXAMPLE.COM  ", password: "secret123", role: "admin")
    assert_equal "admin2@example.com", user.email_address
  end

  test "role defaults to admin on first user" do
    user = User.new(email_address: "new2@example.com", password: "secret")
    user.valid?
    assert_equal "admin", user.role
  end

  test "invalid role rejected" do
    user = User.new(email_address: "x@example.com", password: "secret", role: "superuser")
    assert_not user.valid?
    assert_includes user.errors[:role], "is not included in the list"
  end

  test "admin? returns true only for admin role" do
    assert users(:admin_user).admin?
    assert_not users(:operator_user).admin?
    assert_not users(:readonly_user).admin?
  end

  test "operator? returns true only for operator role" do
    assert users(:operator_user).operator?
    assert_not users(:admin_user).operator?
  end

  test "readonly? returns true only for readonly role" do
    assert users(:readonly_user).readonly?
    assert_not users(:admin_user).readonly?
  end

  test "active_users scope excludes inactive users" do
    assert_includes User.active_users, users(:admin_user)
    assert_not_includes User.active_users, users(:inactive_user)
  end
end

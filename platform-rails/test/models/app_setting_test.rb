require "test_helper"

class AppSettingTest < ActiveSupport::TestCase
  test "get returns value for existing key" do
    assert_equal "RedHusky Test", AppSetting.get("app_name")
  end

  test "get returns default when key missing" do
    assert_equal "fallback", AppSetting.get("nonexistent_key", default: "fallback")
  end

  test "get returns nil when key missing and no default" do
    assert_nil AppSetting.get("nonexistent_key")
  end

  test "set creates a new setting" do
    AppSetting.set("new_key", "new_value")
    assert_equal "new_value", AppSetting.get("new_key")
  end

  test "set updates an existing setting" do
    AppSetting.set("app_name", "Updated Name")
    assert_equal "Updated Name", AppSetting.get("app_name")
  end

  test "key must be unique" do
    AppSetting.create!(key: "unique_test", value: "a")
    dup = AppSetting.new(key: "unique_test", value: "b")
    assert_not dup.valid?
  end
end

require "test_helper"

class AppTemplateTest < ActiveSupport::TestCase
  test "placeholders extracts unique {{VAR}} names in first-seen order" do
    t = AppTemplate.new(compose_yaml: "image: {{IMAGE}}\nname: {{APP_NAME}}\nother: {{IMAGE}}")
    assert_equal [ "IMAGE", "APP_NAME" ], t.placeholders
  end

  test "render_compose substitutes values, blank for missing ones" do
    t = AppTemplate.new(compose_yaml: "image: {{IMAGE}}\ndomain: {{DOMAIN}}")
    rendered = t.render_compose("IMAGE" => "myapp:v1")
    assert_equal "image: myapp:v1\ndomain: ", rendered
  end

  test "render_compose accepts symbol keys too" do
    t = AppTemplate.new(compose_yaml: "image: {{IMAGE}}")
    assert_equal "image: myapp:v1", t.render_compose(IMAGE: "myapp:v1")
  end

  test "check_safety allows a clean compose with named volumes" do
    yaml = <<~YAML
      services:
        web:
          image: nginx
          volumes:
            - data:/var/lib/data
      volumes:
        data: {}
    YAML
    assert_equal [ true, nil ], AppTemplate.check_safety(yaml)
  end

  test "check_safety allows a bind mount under the allowed prefix" do
    yaml = <<~YAML
      services:
        web:
          image: nginx
          volumes:
            - /srv/redhusky/data:/data
    YAML
    assert_equal [ true, nil ], AppTemplate.check_safety(yaml)
  end

  test "check_safety blocks the docker socket" do
    yaml = <<~YAML
      services:
        evil:
          image: alpine
          volumes:
            - /var/run/docker.sock:/var/run/docker.sock
    YAML
    safe, reason = AppTemplate.check_safety(yaml)
    assert_not safe
    assert_match(/socket/, reason)
  end

  test "check_safety blocks a host path outside the allowlist" do
    yaml = <<~YAML
      services:
        evil:
          image: alpine
          volumes:
            - /etc:/host-etc
    YAML
    safe, reason = AppTemplate.check_safety(yaml)
    assert_not safe
    assert_match(/etc/, reason)
  end

  test "check_safety rejects malformed yaml" do
    safe, reason = AppTemplate.check_safety("not: [valid: yaml")
    assert_not safe
    assert_match(/YAML inválido/, reason)
  end

  test "check_safety rejects a non-mapping top level" do
    safe, = AppTemplate.check_safety("- just\n- a\n- list")
    assert_not safe
  end
end

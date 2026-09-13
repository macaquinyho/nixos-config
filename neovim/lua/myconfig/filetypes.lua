-- Filetype associations

vim.filetype.add({
  extension = {
    automount = "systemd",
    caddyfile = "caddy",
    j2 = "jinja",
    jinja = "jinja",
    jinja2 = "jinja",
    mount = "systemd",
    path = "systemd",
    scope = "systemd",
    service = "systemd",
    slice = "systemd",
    socket = "systemd",
    swap = "systemd",
    target = "systemd",
    timer = "systemd",
  },
  filename = { Caddyfile = "caddy" },
  pattern = {
    [".*%.gitlab%-ci%.yml"] = "yaml.gitlab",
    [".*/playbooks/.*%.ya?ml"] = "yaml.ansible",
    [".*/roles/.*%.ya?ml"] = "yaml.ansible",
    [".*/tasks/.*%.ya?ml"] = "yaml.ansible",
    [".*/templates?/.*%.tmpl"] = "gotmpl",
    [".*playbook.*%.ya?ml"] = "yaml.ansible",
  },
})

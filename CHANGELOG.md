## [0.0.2] - 2026-10-12
- Run Studio in its own directory (`~/pegasus-studio` by default, chosen on
  the form) instead of the user's real home, which it used to overwrite
  (Codex/Claude/OpenCode/Pegasus configuration). See README, issue #1.
- Site settings for administrators: /etc/ood/config/apps/bc_pegasus_ai_studio/site.env
  (site catalog, LLM gateway, HTCondor access point), baked in at render time.

## [0.0.1] - 2026-09-28
- Initial release

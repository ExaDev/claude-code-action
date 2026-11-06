# Anchor file only -- never built or executed. Exists so Dependabot's docker ecosystem can
# track this pin. The reference this action actually runs lives in action.yml's headroom_image
# input default -- keep the two in sync by hand (see README.md's "Context compression (Headroom)"
# section): when this digest bumps, update action.yml's default to match in the same PR.
FROM ghcr.io/headroomlabs-ai/headroom@sha256:2bccb27a4c195f643a126876006019e8e8dff40046701b9a0bdaff393df18a0e

# Anchor file only -- never built or executed. Exists so Dependabot's docker ecosystem can
# track this pin. The reference this action actually runs lives in action.yml's headroom_image
# input default -- keep the two in sync by hand (see README.md's "Context compression (Headroom)"
# section): when this digest bumps, update action.yml's default to match in the same PR.
FROM ghcr.io/headroomlabs-ai/headroom@sha256:1ea5e053e3da346f1b2d66af9c3809faa9d99ccb2fae447a7ffe5aae96783a8a

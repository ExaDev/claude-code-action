# Anchor file only -- never built or executed. Exists so Dependabot's docker ecosystem can
# track this pin. The reference this action actually runs lives in action.yml's headroom_image
# input default -- keep the two in sync by hand (see README.md's "Context compression (Headroom)"
# section): when this digest bumps, update action.yml's default to match in the same PR.
FROM ghcr.io/headroomlabs-ai/headroom@sha256:b4173591f02527dd1fadf6fdf0592ff1e1e88c0856b3b479d278bae3d6778876

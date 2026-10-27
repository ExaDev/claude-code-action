# Anchor file only -- never built or executed. Exists so Dependabot's docker ecosystem can
# track this pin. The reference this action actually runs lives in action.yml's headroom_image
# input default -- keep the two in sync by hand (see README.md's "Context compression (Headroom)"
# section): when this digest bumps, update action.yml's default to match in the same PR.
FROM ghcr.io/headroomlabs-ai/headroom@sha256:318b431788f83e0c153ece2975b64b3963060c14e19d1bc4aa773f8fa5bfc00e

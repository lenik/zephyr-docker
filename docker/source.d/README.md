# Container startup hooks (copied to /opt/zephyr/source.d).
# *.sh are sourced by entrypoint.sh; other files run as a subprocess.
# Modules may early-return based on $ROLE (zephyr|backend|web).

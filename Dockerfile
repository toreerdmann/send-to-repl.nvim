# Start with the official UV image (Alpine variant)
FROM ghcr.io/astral-sh/uv:alpine

# 1. Install Neovim and test tools
# Since the base is Alpine, we can just use apk
RUN apk add --no-cache \
    neovim \
    git \
    bash \
    curl \
    # Ensure a python interpreter is available as 'python3' for Neovim providers
    python3

# 2. Install IPython into the system environment
# The UV image is configured to allow this smoothly
RUN uv run --with ipython ipython -c "1+1"

# 3. Workdir setup
WORKDIR /app

# 4. Default command
CMD ["bash", "run_tests.sh"]

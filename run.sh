docker build -t nvim-repl-test .
docker run --rm -v "$(pwd):/app" nvim-repl-test

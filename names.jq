def pname: (.argv0 // .argv[0] // "") | split("/") | last | ltrimstr("-");
def is_shell: test("^(zsh|bash|fish|sh|dash|login)$");

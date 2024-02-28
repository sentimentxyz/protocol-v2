set -e

if command -v genhtml > /dev/null 2>&1; then
    echo "skipping prereqs"
else
    if command -v brew > /dev/null 2>&1; then
        brew install ekhtml lcov
    else
        echo "Please install lcov and genhtml to continue."
        exit 1
    fi
fi

forge coverage --report lcov && genhtml lcov.info --branch-coverage --output-dir coverage

if command -v open > /dev/null 2>&1; then
    open coverage/index.html
else
    echo '\n\n'
    echo "Coverage report generated in coverage/index.html"
fi
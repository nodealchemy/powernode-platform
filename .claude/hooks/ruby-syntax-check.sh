#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ "$FILE_PATH" != *.rb ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

OUTPUT=$(ruby -c "$FILE_PATH" 2>&1)
if [[ $? -ne 0 ]]; then
  echo "Ruby syntax error in $FILE_PATH: $OUTPUT" >&2
  exit 2
fi

# Advisory: check for frozen_string_literal pragma
FIRST_LINE=$(head -1 "$FILE_PATH")
if [[ "$FIRST_LINE" != "# frozen_string_literal: true" ]]; then
  echo "Warning: $FILE_PATH missing '# frozen_string_literal: true' pragma" >&2
fi
exit 0

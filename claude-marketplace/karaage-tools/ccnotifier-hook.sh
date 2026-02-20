#!/bin/bash
# CCNotifier Hook Script
# Enriches Claude Code hook data with terminal context for remote response capability
# Also extracts the actual prompt from the transcript for idle_prompt notifications
# Falls back to raw data if python enrichment fails

SOCKET="/tmp/ccn-501.sock"
INPUT=$(cat)

# idle_prompt の再発火を抑制
# session_id ベースのロックファイルで同じアイドル状態での重複通知を防ぐ
# hook_event_name で正確にイベント種別を判別する
_CCN_PARSED=$(echo "$INPUT" | /usr/bin/python3 -c "
import sys,json
d=json.loads(sys.stdin.read())
print(d.get('hook_event_name',''), d.get('notification_type',''), d.get('session_id',''))
" 2>/dev/null)
_CCN_EVENT=$(echo "$_CCN_PARSED" | cut -d' ' -f1)
_CCN_NOTIF_TYPE=$(echo "$_CCN_PARSED" | cut -d' ' -f2)
_CCN_SESSION_ID=$(echo "$_CCN_PARSED" | cut -d' ' -f3)

if [ -n "$_CCN_SESSION_ID" ]; then
  _CCN_LOCK="/tmp/ccn-idle-sent-${_CCN_SESSION_ID}"
  if [ "$_CCN_NOTIF_TYPE" = "idle_prompt" ]; then
    # 既に通知済みならスキップ
    [ -f "$_CCN_LOCK" ] && exit 0
    touch "$_CCN_LOCK"
  elif [ "$_CCN_EVENT" = "UserPromptSubmit" ]; then
    # ユーザーがプロンプトを送信 → ロックをクリアして次のidleで再通知可能にする
    rm -f "$_CCN_LOCK" 2>/dev/null
  fi
  # PreToolUse等の他イベントではロックに触らない
fi

# Try to enrich with terminal context and extract prompt using python
# Pass input via stdin to avoid shell escaping issues
ENRICHED=$(echo "$INPUT" | /usr/bin/python3 -c "import sys, json, os

def extract_prompt_from_transcript(transcript_path):
    if not transcript_path or not os.path.exists(transcript_path):
        return None
    try:
        last_assistant_msg = None
        with open(transcript_path, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                    if entry.get('type') == 'assistant':
                        msg = entry.get('message', {})
                        content = msg.get('content', [])
                        if isinstance(content, list):
                            for block in content:
                                if isinstance(block, dict) and block.get('type') == 'text':
                                    text = block.get('text', '').strip()
                                    if text:
                                        last_assistant_msg = text
                        elif isinstance(content, str):
                            last_assistant_msg = content.strip()
                except:
                    continue
        return last_assistant_msg
    except:
        return None

def extract_pending_tool_from_transcript(transcript_path):
    '''Extract the last tool_use that hasn't been completed (for permission prompts)'''
    if not transcript_path or not os.path.exists(transcript_path):
        return None, None
    try:
        last_tool_name = None
        last_tool_input = None
        completed_tool_ids = set()
        with open(transcript_path, 'r') as f:
            lines = f.readlines()
        # First pass: collect completed tool IDs
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                if entry.get('type') == 'tool_result':
                    tid = entry.get('tool_use_id')
                    if tid:
                        completed_tool_ids.add(tid)
            except:
                continue
        # Second pass: find last uncompleted tool_use
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                if entry.get('type') == 'assistant':
                    msg = entry.get('message', {})
                    content = msg.get('content', [])
                    if isinstance(content, list):
                        for block in content:
                            if isinstance(block, dict) and block.get('type') == 'tool_use':
                                tid = block.get('id')
                                if tid and tid not in completed_tool_ids:
                                    last_tool_name = block.get('name')
                                    last_tool_input = block.get('input', {})
            except:
                continue
        return last_tool_name, last_tool_input
    except:
        return None, None

def extract_user_questions_from_transcript(transcript_path):
    '''Extract pending AskUserQuestion tool use (for idle_prompt with questions)'''
    if not transcript_path or not os.path.exists(transcript_path):
        return None
    try:
        completed_tool_ids = set()
        with open(transcript_path, 'r') as f:
            lines = f.readlines()
        # First pass: collect completed tool IDs
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                if entry.get('type') == 'tool_result':
                    tid = entry.get('tool_use_id')
                    if tid:
                        completed_tool_ids.add(tid)
            except:
                continue
        # Second pass: find pending AskUserQuestion tool use
        for line in reversed(lines):
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                if entry.get('type') == 'assistant':
                    msg = entry.get('message', {})
                    content = msg.get('content', [])
                    if isinstance(content, list):
                        for block in content:
                            if isinstance(block, dict) and block.get('type') == 'tool_use':
                                tid = block.get('id')
                                tool_name = block.get('name')
                                if tid and tid not in completed_tool_ids and tool_name == 'AskUserQuestion':
                                    tool_input = block.get('input', {})
                                    questions = tool_input.get('questions', [])
                                    if questions:
                                        return questions
            except:
                continue
        return None
    except:
        return None

def extract_plan_content_from_transcript(transcript_path):
    '''Extract plan content when ExitPlanMode is pending.
    The plan is written by Claude to a plan file, and Claude typically summarizes
    or describes the plan in text blocks before calling ExitPlanMode.
    We look for text content in the same assistant turn that contains ExitPlanMode.'''
    if not transcript_path or not os.path.exists(transcript_path):
        return None
    try:
        completed_tool_ids = set()
        with open(transcript_path, 'r') as f:
            lines = f.readlines()
        # First pass: collect completed tool IDs
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                if entry.get('type') == 'tool_result':
                    tid = entry.get('tool_use_id')
                    if tid:
                        completed_tool_ids.add(tid)
            except:
                continue
        # Second pass: find the assistant message containing pending ExitPlanMode
        for line in reversed(lines):
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                if entry.get('type') == 'assistant':
                    msg = entry.get('message', {})
                    content = msg.get('content', [])
                    if not isinstance(content, list):
                        continue
                    # Check if this message has a pending ExitPlanMode
                    has_pending_exit_plan = False
                    for block in content:
                        if isinstance(block, dict) and block.get('type') == 'tool_use':
                            tid = block.get('id')
                            tool_name = block.get('name')
                            if tid and tid not in completed_tool_ids and tool_name == 'ExitPlanMode':
                                has_pending_exit_plan = True
                                break
                    if has_pending_exit_plan:
                        # Collect all text blocks from this message as the plan content
                        text_parts = []
                        for block in content:
                            if isinstance(block, dict) and block.get('type') == 'text':
                                text = block.get('text', '').strip()
                                if text:
                                    text_parts.append(text)
                        if text_parts:
                            return '\n\n'.join(text_parts)
            except:
                continue
        return None
    except:
        return None

try:
    d = json.loads(sys.stdin.read())
    d['terminal_app'] = os.environ.get('TERM_PROGRAM', '')
    d['iterm_session_id'] = os.environ.get('ITERM_SESSION_ID', '')
    d['iterm_profile'] = os.environ.get('ITERM_PROFILE', '')
    d['kitty_window_id'] = os.environ.get('KITTY_WINDOW_ID', '')
    d['kitty_pid'] = os.environ.get('KITTY_PID', '')
    d['tmux_session'] = os.environ.get('TMUX', '')
    d['tmux_pane'] = os.environ.get('TMUX_PANE', '')
    d['terminal_pid'] = str(os.getppid())
    transcript_path = d.get('transcript_path')
    if d.get('notification_type') == 'idle_prompt':
        prompt = extract_prompt_from_transcript(transcript_path)
        if prompt:
            d['prompt'] = prompt  # Send full prompt, no truncation
        # Check for AskUserQuestion prompts
        user_questions = extract_user_questions_from_transcript(transcript_path)
        if user_questions:
            d['user_questions'] = user_questions
    elif d.get('notification_type') == 'permission_prompt':
        # Extract tool info from transcript for permission prompts
        tool_name, tool_input = extract_pending_tool_from_transcript(transcript_path)
        if tool_name and not d.get('tool_name'):
            d['tool_name'] = tool_name
        if tool_input and not d.get('tool_input'):
            d['tool_input'] = tool_input
        # Special handling for ExitPlanMode: extract full plan content
        effective_tool_name = tool_name or d.get('tool_name')
        if effective_tool_name == 'ExitPlanMode':
            plan_content = extract_plan_content_from_transcript(transcript_path)
            if plan_content:
                # Add plan content to tool_input so it gets sent to mobile
                if not d.get('tool_input'):
                    d['tool_input'] = {}
                if isinstance(d['tool_input'], dict):
                    d['tool_input']['planContent'] = plan_content
    print(json.dumps(d))
except:
    pass" 2>/dev/null)

if [ -n "$ENRICHED" ]; then
    echo "$ENRICHED" | /usr/bin/nc -U "$SOCKET"
else
    # Fallback: send raw data without enrichment
    echo "$INPUT" | /usr/bin/nc -U "$SOCKET"
fi
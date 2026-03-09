import os
import subprocess

import streamlit as st
from openai import OpenAI

# --- Configurations ---
# System Prompt for Coach Mode
SYSTEM_PROMPT = """You are a Red Team / Penetration Testing Coach in an isolated lab environment.
Your purpose is to coach the student, analyze their terminal output, and suggest logical next steps.

CRITICAL RULES:
1. DO NOT execute commands for the user.
2. DO NOT provide full exploit scripts meant for automated exploitation.
3. DO EXPLAIN concepts, tool usage, and potential misconfigurations in the context the student provides.
4. DO SUGGEST the next phase (e.g., Recon -> Enumeration -> Exploitation).
5. Always respond in markdown. Be concise and educational.
"""

MODELS = {
    "Groq: Llama3 8B": {"model": "llama3-8b-8192", "base_url": "https://api.groq.com/openai/v1"},
    "Groq: Llama3 70B": {"model": "llama3-70b-8192", "base_url": "https://api.groq.com/openai/v1"},
    "OpenRouter: Claude 3 Haiku": {"model": "anthropic/claude-3-haiku", "base_url": "https://openrouter.ai/api/v1"},
    "OpenRouter: Claude 3.5 Sonnet": {"model": "anthropic/claude-3.5-sonnet", "base_url": "https://openrouter.ai/api/v1"},
    "Together: Llama 3 70B": {"model": "meta-llama/Llama-3-70b-chat-hf", "base_url": "https://api.together.xyz/v1"},
    "OpenAI: GPT-4o": {"model": "gpt-4o", "base_url": "https://api.openai.com/v1"},
    "OpenAI: GPT-3.5 Turbo": {"model": "gpt-3.5-turbo", "base_url": "https://api.openai.com/v1"},
}


def get_env_int(name: str, default: int, min_value: int, max_value: int) -> int:
    raw = os.getenv(name)
    if raw is None or raw == "":
        return default
    try:
        value = int(raw)
    except ValueError:
        return default
    return max(min_value, min(max_value, value))


TMUX_SESSION = os.getenv("RED_TMUX_SESSION", "red_session")
CONTEXT_LINES = get_env_int("RED_ASSISTANT_CONTEXT_LINES", 100, 20, 1000)
MAX_HISTORY = get_env_int("RED_ASSISTANT_MAX_HISTORY", 6, 2, 20)

st.set_page_config(page_title="Red Lab AI Coach", page_icon="RS", layout="wide")
st.title("Red Lab AI Coaching Assistant")

# --- Sidebar Configuration ---
with st.sidebar:
    st.header("Configuration")
    st.markdown("Enter your Bring-Your-Own (BYO) API Key below. Keys are not saved permanently.")

    selected_model_name = st.selectbox("Select Provider / Model:", list(MODELS.keys()))
    provider_config = MODELS[selected_model_name]

    api_key = st.text_input("API Key (Groq, OpenAI, OpenRouter, etc):", type="password")

    st.markdown("---")
    st.markdown("### How It Works")
    st.markdown(
        "When you ask a question, the assistant reads the last "
        f"{CONTEXT_LINES} lines of your tmux session `{TMUX_SESSION}` "
        "and provides targeted coaching."
    )
    st.caption(f"History sent to model: last {MAX_HISTORY} messages")

# --- Session State ---
if "messages" not in st.session_state:
    st.session_state["messages"] = []


def get_tmux_context(lines: int) -> str:
    """Extracts the last N lines from the tmux session."""
    try:
        result = subprocess.run(
            ["tmux", "capture-pane", "-t", TMUX_SESSION, "-pS", f"-{lines}"],
            capture_output=True,
            text=True,
            check=True,
            timeout=2,
        )
        output = result.stdout.strip()
        return output if output else "[tmux returned no output]"
    except subprocess.TimeoutExpired:
        return "[tmux capture timed out]"
    except subprocess.CalledProcessError as e:
        return (
            f"[Error capturing tmux context. Make sure tmux session '{TMUX_SESSION}' exists. "
            f"Error: {e}]"
        )
    except FileNotFoundError:
        return "[tmux command not found.]"


def build_user_payload(question: str, context: str, lines: int) -> str:
    return (
        f"User Question: {question}\n\n"
        f"--- TERMINAL CONTEXT (last {lines} lines) ---\n"
        f"{context}\n"
        f"---------------------------------------------\n"
    )


def build_ai_messages() -> list[dict]:
    ai_messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    history = st.session_state["messages"][-MAX_HISTORY:]
    for msg in history:
        ai_messages.append({"role": msg["role"], "content": msg["content"]})
    return ai_messages


# --- Main Interaction ---
for msg in st.session_state["messages"]:
    with st.chat_message(msg["role"]):
        st.markdown(msg["display_content"])

user_input = st.chat_input("Ask a question about your current terminal state (e.g., 'Why did sqlmap fail?')...")

if user_input:
    if not api_key:
        st.error("Please enter an API Key in the sidebar.")
        st.stop()

    # Save user message for UI/history (without terminal context)
    st.session_state["messages"].append(
        {"role": "user", "content": user_input, "display_content": user_input}
    )
    with st.chat_message("user"):
        st.markdown(user_input)

    terminal_context = get_tmux_context(CONTEXT_LINES)
    ai_messages = build_ai_messages()
    user_payload = build_user_payload(user_input, terminal_context, CONTEXT_LINES)

    if ai_messages and ai_messages[-1]["role"] == "user":
        ai_messages[-1]["content"] = user_payload
    else:
        ai_messages.append({"role": "user", "content": user_payload})

    client = OpenAI(
        base_url=provider_config["base_url"],
        api_key=api_key,
    )

    with st.chat_message("assistant"):
        message_placeholder = st.empty()
        with st.spinner(f"Analyzing context via {selected_model_name}..."):
            try:
                extra_headers = {}
                if "openrouter" in provider_config["base_url"]:
                    extra_headers = {
                        "HTTP-Referer": "https://github.com/red-lab-assistant",
                        "X-Title": "Red Lab Coach",
                    }

                stream = client.chat.completions.create(
                    model=provider_config["model"],
                    messages=ai_messages,
                    temperature=0.5,
                    stream=True,
                    extra_headers=extra_headers if extra_headers else None,
                )

                full_response = ""
                for chunk in stream:
                    if chunk.choices and chunk.choices[0].delta.content is not None:
                        full_response += chunk.choices[0].delta.content
                        message_placeholder.markdown(full_response + " ...")

                message_placeholder.markdown(full_response)
                st.session_state["messages"].append(
                    {
                        "role": "assistant",
                        "content": full_response,
                        "display_content": full_response,
                    }
                )
            except Exception as e:
                error_msg = f"Error reaching provider API: {e}"
                message_placeholder.error(error_msg)
                st.session_state["messages"].append(
                    {"role": "assistant", "content": error_msg, "display_content": error_msg}
                )

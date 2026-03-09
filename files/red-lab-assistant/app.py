import streamlit as st
import subprocess
import requests
import json
import os

# --- Configurations ---
GATEWAY_URL = os.environ.get("GATEWAY_URL", "http://10.99.99.10:8000/v1/chat/completions") # Adjust to VLAN 99 IP

st.set_page_config(page_title="Red Lab AI Coach", page_icon="🤖", layout="wide")
st.title("🛡️ Red Lab AI Coaching Assistant")

# --- Default Models based on typical usage ---
MODELS = [
    "openai/gpt-3.5-turbo",
    "openai/gpt-4o",
    "groq/llama3-8b-8192",
    "groq/llama3-70b-8192",
    "openrouter/anthropic/claude-3-haiku",
    "openrouter/anthropic/claude-3-opus",
    "together_ai/meta-llama/Llama-3-70b-chat-hf"
]

# --- Sidebar Configuration ---
with st.sidebar:
    st.header("⚙️ Configuration")
    st.markdown("Enter your Bring-Your-Own (BYO) API Key below. Keys are **not** saved permanently.")
    
    selected_model = st.selectbox("Select Model Wrapper (LiteLLM format):", MODELS)
    api_key = st.text_input("API Key (Groq, OpenAI, OpenRouter, etc):", type="password")

    st.markdown("---")
    st.markdown("### How It Works")
    st.markdown("When you click **Ask Coach**, the assistant automatically reads the last 100 lines of your terminal (tmux session `red_session`). It understands your context and provides targeted advice on Web Pentesting.")

# --- Session State ---
if "messages" not in st.session_state:
    st.session_state["messages"] = []

# --- Helper Functions ---
def get_tmux_context():
    """Extracts the last 100 lines from the tmux session named 'red_session'"""
    try:
        # Run tmux capture-pane command
        result = subprocess.run(
            ["tmux", "capture-pane", "-t", "red_session", "-pS", "-100"],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        return f"[Error capturing tmux context. Make sure you are using 'tmux' on the terminal. Error: {e}]"
    except FileNotFoundError:
        return "[tmux command not found.]"

# --- Main Interaction ---
for msg in st.session_state.messages:
    if msg["role"] == "user":
        with st.chat_message("user"):
            st.markdown(msg["display_content"])
    elif msg["role"] == "assistant":
        with st.chat_message("assistant"):
            st.markdown(msg["content"])

user_input = st.chat_input("Ask a question about your current terminal state (e.g., 'Why did sqlmap fail?')...")

if user_input:
    if not api_key:
        st.error("Please enter an API Key in the sidebar.")
        st.stop()

    # Get local terminal context
    terminal_context = get_tmux_context()

    # Formulate the hidden AI Prompt vs the Display Prompt
    display_msg = user_input
    hidden_ai_prompt = (
        f"User Question: {user_input}\n\n"
        f"--- TERMINAL CONTEXT ---\n"
        f"{terminal_context}\n"
        f"------------------------\n"
    )

    # Append to Chat UI
    st.session_state.messages.append({"role": "user", "display_content": display_msg, "content": hidden_ai_prompt})
    with st.chat_message("user"):
        st.markdown(display_msg)
    
    with st.chat_message("assistant"):
        message_placeholder = st.empty()
        
        # Build litellm payload to Gateway
        # Only sending the actual content meant for the AI
        payload = {
            "model": selected_model,
            "messages": [{"role": m["role"], "content": m["content"]} for m in st.session_state.messages],
            "temperature": 0.5,
            "stream": False
        }
        
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        
        with st.spinner("Analyzing context via Gateway..."):
            try:
                response = requests.post(GATEWAY_URL, json=payload, headers=headers, timeout=60)
                if response.status_code == 200:
                    result = response.json()
                    ai_reply = result["choices"][0]["message"]["content"]
                    message_placeholder.markdown(ai_reply)
                    st.session_state.messages.append({"role": "assistant", "content": ai_reply, "display_content": ai_reply})
                else:
                    message_placeholder.error(f"Gateway Error {response.status_code}: {response.text}")
                    st.session_state.messages.pop() # remove failed message
            except Exception as e:
                message_placeholder.error(f"Network Error reaching Gateway: {e}")
                st.session_state.messages.pop()

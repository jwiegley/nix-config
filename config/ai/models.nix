_:

let
  providers = builtins.fromJSON ''
    {
      "positron-anthropic": {
        "sourceOrder": 0,
        "displayName": "Positron",
        "baseUrl": "https://api.anthropic.com",
        "apiKey": {
          "env": "ANTHROPIC_API_KEY"
        },
        "selectors": {
          "clients": [
            "droid",
            "pi"
          ]
        },
        "droid": {
          "providerType": "anthropic"
        }
      },
      "positron-google": {
        "sourceOrder": 1,
        "displayName": "Positron",
        "baseUrl": "https://generativelanguage.googleapis.com/v1beta/",
        "apiKey": {
          "env": "GEMINI_API_KEY"
        },
        "selectors": {
          "clients": [
            "droid",
            "pi"
          ]
        },
        "droid": {
          "providerType": "generic-chat-completion-api",
          "noImageSupport": true
        }
      },
      "positron-openai": {
        "sourceOrder": 2,
        "displayName": "Positron",
        "baseUrl": "https://api.openai.com/v1",
        "apiKey": {
          "env": "OPENAI_API_KEY"
        },
        "selectors": {
          "clients": [
            "droid",
            "pi"
          ]
        },
        "droid": {
          "providerType": "openai"
        }
      },
      "nvidia": {
        "sourceOrder": 3,
        "displayName": "NVIDIA",
        "baseUrl": "https://integrate.api.nvidia.com/v1",
        "apiKey": {
          "env": "NVIDIA_API_KEY"
        },
        "selectors": {
          "clients": [
            "droid",
            "opencode",
            "pi"
          ]
        },
        "droid": {
          "providerType": "openai"
        },
        "opencode": {
          "npm": "@ai-sdk/openai-compatible",
          "name": "NVIDIA",
          "timeout": false
        }
      },
      "litellm": {
        "sourceOrder": 4,
        "displayName": "LiteLLM",
        "baseUrl": "https://litellm.vulcan.lan/v1/",
        "apiKey": {
          "env": "LITELLM_API_KEY"
        },
        "selectors": {
          "clients": [
            "droid",
            "opencode",
            "pi"
          ],
          "excludeProfiles": [
            "vulcan-opencode"
          ]
        },
        "droid": {
          "providerType": "generic-chat-completion-api",
          "noImageSupport": true,
          "extraArgs": {
            "min_p": 0,
            "temperature": 1,
            "top_p": 1
          },
          "extraHeaders": {
            "x-litellm-tags": "droid"
          }
        },
        "opencode": {
          "npm": "@ai-sdk/openai-compatible",
          "name": "LiteLLM",
          "timeout": false
        }
      },
      "llama-cpp-remote": {
        "sourceOrder": 5,
        "displayName": "Llama.cpp (Remote)",
        "baseUrl": "https://10.6.0.1/v1/",
        "apiKey": {
          "nonSecret": "dummy-api-key"
        },
        "selectors": {
          "clients": [
            "droid",
            "opencode"
          ],
          "hosts": [
            "clio"
          ]
        },
        "droid": {
          "providerType": "generic-chat-completion-api",
          "noImageSupport": true
        },
        "opencode": {
          "npm": "@ai-sdk/openai-compatible",
          "name": "Llama-Swap (Remote)",
          "timeout": false
        }
      },
      "omlx": {
        "sourceOrder": 6,
        "displayName": "oMLX",
        "baseUrl": "http://hera.lan:8000/v1",
        "apiKey": {
          "nonSecret": "dummy-key"
        },
        "selectors": {
          "clients": [
            "droid",
            "opencode",
            "pi"
          ]
        },
        "droid": {
          "providerType": "generic-chat-completion-api",
          "noImageSupport": true
        },
        "opencode": {
          "npm": "@ai-sdk/openai-compatible",
          "name": "oMLX",
          "timeout": false
        }
      },
      "llama-cpp-local": {
        "sourceOrder": 7,
        "displayName": "Llama.cpp",
        "baseUrl": "http://localhost:8080/v1",
        "apiKey": {
          "nonSecret": "not-needed"
        },
        "selectors": {
          "clients": [
            "droid",
            "opencode",
            "pi"
          ]
        },
        "droid": {
          "providerType": "generic-chat-completion-api",
          "noImageSupport": true
        },
        "opencode": {
          "npm": "@ai-sdk/openai-compatible",
          "name": "Llama-Swap",
          "timeout": false
        }
      }
    }  '';

  models = builtins.fromJSON ''
    {
      "positron-anthropic/claude-fable-5": {
        "sourceOrder": 0,
        "provider": "positron-anthropic",
        "id": "claude-fable-5",
        "displayName": "Claude Fable 5",
        "maxOutputTokens": 32768,
        "selectors": {}
      },
      "positron-anthropic/claude-haiku-4-5-20251001": {
        "sourceOrder": 1,
        "provider": "positron-anthropic",
        "id": "claude-haiku-4-5-20251001",
        "displayName": "Claude Haiku 4.5",
        "maxOutputTokens": 32768,
        "selectors": {}
      },
      "positron-anthropic/claude-opus-4-7": {
        "sourceOrder": 2,
        "provider": "positron-anthropic",
        "id": "claude-opus-4-7",
        "displayName": "Claude Opus 4.7",
        "maxOutputTokens": 32768,
        "selectors": {}
      },
      "positron-anthropic/claude-sonnet-4-6": {
        "sourceOrder": 3,
        "provider": "positron-anthropic",
        "id": "claude-sonnet-4-6",
        "displayName": "Claude Sonnet 4.6",
        "maxOutputTokens": 32768,
        "selectors": {}
      },
      "positron-google/gemini-3-pro-preview": {
        "sourceOrder": 4,
        "provider": "positron-google",
        "id": "gemini-3-pro-preview",
        "displayName": "Gemini 3 Pro Preview",
        "maxOutputTokens": 32000,
        "selectors": {}
      },
      "positron-google/gemini-3.1-pro-preview": {
        "sourceOrder": 5,
        "provider": "positron-google",
        "id": "gemini-3.1-pro-preview",
        "displayName": "Gemini 3.1 Pro Preview",
        "maxOutputTokens": 32000,
        "selectors": {}
      },
      "positron-openai/gpt-5.5": {
        "sourceOrder": 6,
        "provider": "positron-openai",
        "id": "gpt-5.5",
        "displayName": "ChatGPT 5.5",
        "maxOutputTokens": 32000,
        "selectors": {}
      },
      "nvidia/qwen/qwen3-coder-480b-a35b-instruct": {
        "sourceOrder": 7,
        "provider": "nvidia",
        "id": "qwen/qwen3-coder-480b-a35b-instruct",
        "displayName": "Qwen3 Coder 480B A35B Instruct",
        "maxOutputTokens": 81920,
        "selectors": {}
      },
      "litellm/hera/Bonsai-8B": {
        "sourceOrder": 8,
        "provider": "litellm",
        "id": "hera/Bonsai-8B",
        "displayName": "Bonsai 8B",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 131072,
        "outputLimit": 65536
      },
      "litellm/hera/claude-fable-5-thinking-32000": {
        "sourceOrder": 9,
        "provider": "litellm",
        "id": "hera/claude-fable-5-thinking-32000",
        "displayName": "Claude Fable 5 (Thinking)",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/claude-fable-5": {
        "sourceOrder": 10,
        "provider": "litellm",
        "id": "hera/claude-fable-5",
        "displayName": "Claude Fable 5",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/positron_anthropic/claude-fable-5": {
        "sourceOrder": 11,
        "provider": "litellm",
        "id": "positron_anthropic/claude-fable-5",
        "displayName": "Claude Fable 5",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/anthropic/claude-fable-5": {
        "sourceOrder": 12,
        "provider": "litellm",
        "id": "anthropic/claude-fable-5",
        "displayName": "Claude Fable 5",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/claude-haiku-4-5-20251001": {
        "sourceOrder": 13,
        "provider": "litellm",
        "id": "hera/claude-haiku-4-5-20251001",
        "displayName": "Claude Haiku 4.5",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/positron_anthropic/claude-haiku-4-5-20251001": {
        "sourceOrder": 14,
        "provider": "litellm",
        "id": "positron_anthropic/claude-haiku-4-5-20251001",
        "displayName": "Claude Haiku 4.5",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/anthropic/claude-haiku-4-5-20251001": {
        "sourceOrder": 15,
        "provider": "litellm",
        "id": "anthropic/claude-haiku-4-5-20251001",
        "displayName": "Claude Haiku 4.5",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/claude-opus-4-7-thinking-32000": {
        "sourceOrder": 16,
        "provider": "litellm",
        "id": "hera/claude-opus-4-7-thinking-32000",
        "displayName": "Claude Opus 4.7 (Thinking)",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/claude-opus-4-7": {
        "sourceOrder": 17,
        "provider": "litellm",
        "id": "hera/claude-opus-4-7",
        "displayName": "Claude Opus 4.7",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/positron_anthropic/claude-opus-4-7": {
        "sourceOrder": 18,
        "provider": "litellm",
        "id": "positron_anthropic/claude-opus-4-7",
        "displayName": "Claude Opus 4.7",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/anthropic/claude-opus-4-7": {
        "sourceOrder": 19,
        "provider": "litellm",
        "id": "anthropic/claude-opus-4-7",
        "displayName": "Claude Opus 4.7",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/claude-sonnet-4-6-thinking-32000": {
        "sourceOrder": 20,
        "provider": "litellm",
        "id": "hera/claude-sonnet-4-6-thinking-32000",
        "displayName": "Claude Sonnet 4.6 (Thinking)",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/claude-sonnet-4-6": {
        "sourceOrder": 21,
        "provider": "litellm",
        "id": "hera/claude-sonnet-4-6",
        "displayName": "Claude Sonnet 4.6",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/positron_anthropic/claude-sonnet-4-6": {
        "sourceOrder": 22,
        "provider": "litellm",
        "id": "positron_anthropic/claude-sonnet-4-6",
        "displayName": "Claude Sonnet 4.6",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/anthropic/claude-sonnet-4-6": {
        "sourceOrder": 23,
        "provider": "litellm",
        "id": "anthropic/claude-sonnet-4-6",
        "displayName": "Claude Sonnet 4.6",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/omlx/cohere-transcribe-03-2026-mlx-fp16": {
        "sourceOrder": 24,
        "provider": "litellm",
        "id": "hera/omlx/cohere-transcribe-03-2026-mlx-fp16",
        "displayName": "Cohere Transcribe 03 2026 MLX Fp 16 (MLX)",
        "maxOutputTokens": 65536,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/cohere-transcribe-03-2026": {
        "sourceOrder": 25,
        "provider": "litellm",
        "id": "hera/cohere-transcribe-03-2026",
        "displayName": "Cohere Transcribe 03",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/mlx-community/deepseek-ai-DeepSeek-V4-Flash-8bit": {
        "sourceOrder": 26,
        "provider": "litellm",
        "id": "hera/mlx-community/deepseek-ai-DeepSeek-V4-Flash-8bit",
        "displayName": "Deepseek Ai Deepseek V 4 Flash (MLX)",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/omlx/deepseek-ai-DeepSeek-V4-Flash-8bit": {
        "sourceOrder": 27,
        "provider": "litellm",
        "id": "hera/omlx/deepseek-ai-DeepSeek-V4-Flash-8bit",
        "displayName": "Deepseek Ai Deepseek V 4 Flash (MLX)",
        "maxOutputTokens": 65536,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/openrouter/z-ai/glm-5.2": {
        "sourceOrder": 28,
        "provider": "litellm",
        "id": "openrouter/z-ai/glm-5.2",
        "displayName": "GLM 5.2",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 1048576,
        "outputLimit": 65536
      },
      "litellm/positron_gemini/gemini-3-pro-preview": {
        "sourceOrder": 29,
        "provider": "litellm",
        "id": "positron_gemini/gemini-3-pro-preview",
        "displayName": "Gemini 3 Pro Preview",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/positron_gemini/gemini-3.1-pro-preview": {
        "sourceOrder": 30,
        "provider": "litellm",
        "id": "positron_gemini/gemini-3.1-pro-preview",
        "displayName": "Gemini 3.1 Pro Preview",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/GLM-4.7-Flash": {
        "sourceOrder": 31,
        "provider": "litellm",
        "id": "hera/GLM-4.7-Flash",
        "displayName": "GLM 4.7 Flash",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 202752,
        "outputLimit": 65536
      },
      "litellm/hera/GLM-5.2": {
        "sourceOrder": 32,
        "provider": "litellm",
        "id": "hera/GLM-5.2",
        "displayName": "GLM 5.2",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 200000,
        "outputLimit": 65536
      },
      "litellm/positron_openai/gpt-5.5": {
        "sourceOrder": 33,
        "provider": "litellm",
        "id": "positron_openai/gpt-5.5",
        "displayName": "ChatGPT 5.5",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/gpt-oss-120b": {
        "sourceOrder": 34,
        "provider": "litellm",
        "id": "hera/gpt-oss-120b",
        "displayName": "GPT-OSS 120B",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 131072,
        "outputLimit": 65536
      },
      "litellm/hera/gpt-oss-20b": {
        "sourceOrder": 35,
        "provider": "litellm",
        "id": "hera/gpt-oss-20b",
        "displayName": "GPT-OSS 20B",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 131072,
        "outputLimit": 65536
      },
      "litellm/hera/gpt-oss-safeguard-20b": {
        "sourceOrder": 36,
        "provider": "litellm",
        "id": "hera/gpt-oss-safeguard-20b",
        "displayName": "GPT-OSS Safeguard 20B",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 131072,
        "outputLimit": 65536
      },
      "litellm/hera/granite-speech-4.1-2b": {
        "sourceOrder": 37,
        "provider": "litellm",
        "id": "hera/granite-speech-4.1-2b",
        "displayName": "Granite Speech 4.1 2B",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/Huihui-Qwable-3.6-27b-abliterated-MTP": {
        "sourceOrder": 38,
        "provider": "litellm",
        "id": "hera/Huihui-Qwable-3.6-27b-abliterated-MTP",
        "displayName": "Huihui Qwable 3.6 27B Abliterated Mtp",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/LFM2.5-350M": {
        "sourceOrder": 39,
        "provider": "litellm",
        "id": "hera/LFM2.5-350M",
        "displayName": "LFM 2.5 350M",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 131072,
        "outputLimit": 65536
      },
      "litellm/hera/GreenBitAI/Llama-2-13B-layer-mix-bpw-2.2-mlx": {
        "sourceOrder": 40,
        "provider": "litellm",
        "id": "hera/GreenBitAI/Llama-2-13B-layer-mix-bpw-2.2-mlx",
        "displayName": "Llama 2 13B Layer Mix Bpw 2.2 (MLX)",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/GreenBitAI/Llama-2-13B-layer-mix-bpw-2.5-mlx": {
        "sourceOrder": 41,
        "provider": "litellm",
        "id": "hera/GreenBitAI/Llama-2-13B-layer-mix-bpw-2.5-mlx",
        "displayName": "Llama 2 13B Layer Mix Bpw 2.5 (MLX)",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/GreenBitAI/Llama-2-13B-layer-mix-bpw-3.0-mlx": {
        "sourceOrder": 42,
        "provider": "litellm",
        "id": "hera/GreenBitAI/Llama-2-13B-layer-mix-bpw-3.0-mlx",
        "displayName": "Llama 2 13B Layer Mix Bpw 3.0 (MLX)",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/positron/llama-3.3-70b-instruct-good-tp2": {
        "sourceOrder": 43,
        "provider": "litellm",
        "id": "positron/llama-3.3-70b-instruct-good-tp2",
        "displayName": "Llama 3.3 70B Instruct Good Tp 2",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/groq/llama-3.3-70b-versatile": {
        "sourceOrder": 44,
        "provider": "litellm",
        "id": "groq/llama-3.3-70b-versatile",
        "displayName": "Llama 3.3 70B Versatile",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/Meta-Llama-3.1-8B": {
        "sourceOrder": 45,
        "provider": "litellm",
        "id": "hera/Meta-Llama-3.1-8B",
        "displayName": "Meta Llama 3.1 8B",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/Nemotron-3-Nano-30B-A3B": {
        "sourceOrder": 46,
        "provider": "litellm",
        "id": "hera/Nemotron-3-Nano-30B-A3B",
        "displayName": "Nemotron 3 Nano 30B",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 1048576,
        "outputLimit": 65536
      },
      "litellm/hera/Nemotron-Cascade-2-30B-A3B": {
        "sourceOrder": 47,
        "provider": "litellm",
        "id": "hera/Nemotron-Cascade-2-30B-A3B",
        "displayName": "Nemotron Cascade 2 30B",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/NVIDIA-Nemotron-3-Super-120B-A12B": {
        "sourceOrder": 48,
        "provider": "litellm",
        "id": "hera/NVIDIA-Nemotron-3-Super-120B-A12B",
        "displayName": "NVIDIA Nemotron 3 Super 120B",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 1048576,
        "outputLimit": 65536
      },
      "litellm/hera/Phi-4-reasoning-plus": {
        "sourceOrder": 49,
        "provider": "litellm",
        "id": "hera/Phi-4-reasoning-plus",
        "displayName": "Phi 4 Reasoning Plus",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 32768,
        "outputLimit": 65536
      },
      "litellm/hera/omlx/Qwen3.6-27B-oQ4e-mtp": {
        "sourceOrder": 50,
        "provider": "litellm",
        "id": "hera/omlx/Qwen3.6-27B-oQ4e-mtp",
        "displayName": "Qwen 3.6 27B Oq 4E Mtp (MLX)",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/omlx/Qwen3.6-27B-oQ8-mtp": {
        "sourceOrder": 51,
        "provider": "litellm",
        "id": "hera/omlx/Qwen3.6-27B-oQ8-mtp",
        "displayName": "Qwen 3.6 27B Oq 8 Mtp (MLX)",
        "maxOutputTokens": 65536,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/omlx/Qwen3.6-35B-A3B-oQ4-mtp": {
        "sourceOrder": 52,
        "provider": "litellm",
        "id": "hera/omlx/Qwen3.6-35B-A3B-oQ4-mtp",
        "displayName": "Qwen 3.6 35B A 3B Oq 4 Mtp (MLX)",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/Qwopus3.5-27B-v3": {
        "sourceOrder": 53,
        "provider": "litellm",
        "id": "hera/Qwopus3.5-27B-v3",
        "displayName": "Qwopus 3.5 27B V 3",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/SERA-32B": {
        "sourceOrder": 54,
        "provider": "litellm",
        "id": "hera/SERA-32B",
        "displayName": "SERA 32B",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 40960,
        "outputLimit": 65536
      },
      "litellm/hera/thesven": {
        "sourceOrder": 55,
        "provider": "litellm",
        "id": "hera/thesven",
        "displayName": "Thesven",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/atorsvn/TinyLlama-1.1B-Chat-v0.1-gptq-4bit": {
        "sourceOrder": 56,
        "provider": "litellm",
        "id": "hera/atorsvn/TinyLlama-1.1B-Chat-v0.1-gptq-4bit",
        "displayName": "Tinyllama 1.1B Chat V 0.1 Gptq (MLX)",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "litellm/hera/atorsvn/TinyLlama-1.1B-step-50K-105b-gptq-4bit": {
        "sourceOrder": 57,
        "provider": "litellm",
        "id": "hera/atorsvn/TinyLlama-1.1B-step-50K-105b-gptq-4bit",
        "displayName": "Tinyllama 1.1B Step 50K 105B Gptq (MLX)",
        "maxOutputTokens": 65536,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "llama-cpp-remote/Bonsai-8B": {
        "sourceOrder": 58,
        "provider": "llama-cpp-remote",
        "id": "Bonsai-8B",
        "displayName": "Bonsai 8B",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/cohere-transcribe-03-2026": {
        "sourceOrder": 59,
        "provider": "llama-cpp-remote",
        "id": "cohere-transcribe-03-2026",
        "displayName": "Cohere Transcribe 03",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/mlx-community/deepseek-ai-DeepSeek-V4-Flash-8bit": {
        "sourceOrder": 60,
        "provider": "llama-cpp-remote",
        "id": "mlx-community/deepseek-ai-DeepSeek-V4-Flash-8bit",
        "displayName": "Deepseek Ai Deepseek V 4 Flash (MLX)",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/GLM-4.7-Flash": {
        "sourceOrder": 61,
        "provider": "llama-cpp-remote",
        "id": "GLM-4.7-Flash",
        "displayName": "GLM 4.7 Flash",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/GLM-5.2": {
        "sourceOrder": 62,
        "provider": "llama-cpp-remote",
        "id": "GLM-5.2",
        "displayName": "GLM 5.2",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/gpt-oss-120b": {
        "sourceOrder": 63,
        "provider": "llama-cpp-remote",
        "id": "gpt-oss-120b",
        "displayName": "GPT-OSS 120B",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/gpt-oss-20b": {
        "sourceOrder": 64,
        "provider": "llama-cpp-remote",
        "id": "gpt-oss-20b",
        "displayName": "GPT-OSS 20B",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/gpt-oss-safeguard-20b": {
        "sourceOrder": 65,
        "provider": "llama-cpp-remote",
        "id": "gpt-oss-safeguard-20b",
        "displayName": "GPT-OSS Safeguard 20B",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/granite-speech-4.1-2b": {
        "sourceOrder": 66,
        "provider": "llama-cpp-remote",
        "id": "granite-speech-4.1-2b",
        "displayName": "Granite Speech 4.1 2B",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/Huihui-Qwable-3.6-27b-abliterated-MTP": {
        "sourceOrder": 67,
        "provider": "llama-cpp-remote",
        "id": "Huihui-Qwable-3.6-27b-abliterated-MTP",
        "displayName": "Huihui Qwable 3.6 27B Abliterated Mtp",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/LFM2.5-350M": {
        "sourceOrder": 68,
        "provider": "llama-cpp-remote",
        "id": "LFM2.5-350M",
        "displayName": "LFM 2.5 350M",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/GreenBitAI/Llama-2-13B-layer-mix-bpw-2.2-mlx": {
        "sourceOrder": 69,
        "provider": "llama-cpp-remote",
        "id": "GreenBitAI/Llama-2-13B-layer-mix-bpw-2.2-mlx",
        "displayName": "Llama 2 13B Layer Mix Bpw 2.2 (MLX)",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/GreenBitAI/Llama-2-13B-layer-mix-bpw-2.5-mlx": {
        "sourceOrder": 70,
        "provider": "llama-cpp-remote",
        "id": "GreenBitAI/Llama-2-13B-layer-mix-bpw-2.5-mlx",
        "displayName": "Llama 2 13B Layer Mix Bpw 2.5 (MLX)",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/GreenBitAI/Llama-2-13B-layer-mix-bpw-3.0-mlx": {
        "sourceOrder": 71,
        "provider": "llama-cpp-remote",
        "id": "GreenBitAI/Llama-2-13B-layer-mix-bpw-3.0-mlx",
        "displayName": "Llama 2 13B Layer Mix Bpw 3.0 (MLX)",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/Meta-Llama-3.1-8B": {
        "sourceOrder": 72,
        "provider": "llama-cpp-remote",
        "id": "Meta-Llama-3.1-8B",
        "displayName": "Meta Llama 3.1 8B",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/Nemotron-3-Nano-30B-A3B": {
        "sourceOrder": 73,
        "provider": "llama-cpp-remote",
        "id": "Nemotron-3-Nano-30B-A3B",
        "displayName": "Nemotron 3 Nano 30B",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/Nemotron-Cascade-2-30B-A3B": {
        "sourceOrder": 74,
        "provider": "llama-cpp-remote",
        "id": "Nemotron-Cascade-2-30B-A3B",
        "displayName": "Nemotron Cascade 2 30B",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/NVIDIA-Nemotron-3-Super-120B-A12B": {
        "sourceOrder": 75,
        "provider": "llama-cpp-remote",
        "id": "NVIDIA-Nemotron-3-Super-120B-A12B",
        "displayName": "NVIDIA Nemotron 3 Super 120B",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/Phi-4-reasoning-plus": {
        "sourceOrder": 76,
        "provider": "llama-cpp-remote",
        "id": "Phi-4-reasoning-plus",
        "displayName": "Phi 4 Reasoning Plus",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/Qwopus3.5-27B-v3": {
        "sourceOrder": 77,
        "provider": "llama-cpp-remote",
        "id": "Qwopus3.5-27B-v3",
        "displayName": "Qwopus 3.5 27B V 3",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/SERA-32B": {
        "sourceOrder": 78,
        "provider": "llama-cpp-remote",
        "id": "SERA-32B",
        "displayName": "SERA 32B",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/thesven": {
        "sourceOrder": 79,
        "provider": "llama-cpp-remote",
        "id": "thesven",
        "displayName": "Thesven",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/atorsvn/TinyLlama-1.1B-Chat-v0.1-gptq-4bit": {
        "sourceOrder": 80,
        "provider": "llama-cpp-remote",
        "id": "atorsvn/TinyLlama-1.1B-Chat-v0.1-gptq-4bit",
        "displayName": "Tinyllama 1.1B Chat V 0.1 Gptq (MLX)",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "llama-cpp-remote/atorsvn/TinyLlama-1.1B-step-50K-105b-gptq-4bit": {
        "sourceOrder": 81,
        "provider": "llama-cpp-remote",
        "id": "atorsvn/TinyLlama-1.1B-step-50K-105b-gptq-4bit",
        "displayName": "Tinyllama 1.1B Step 50K 105B Gptq (MLX)",
        "maxOutputTokens": 128000,
        "selectors": {}
      },
      "omlx/cohere-transcribe-03-2026-mlx-fp16": {
        "sourceOrder": 82,
        "provider": "omlx",
        "id": "cohere-transcribe-03-2026-mlx-fp16",
        "displayName": "Cohere Transcribe 03 2026 MLX Fp 16 (MLX)",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "omlx/deepseek-ai-DeepSeek-V4-Flash-8bit": {
        "sourceOrder": 83,
        "provider": "omlx",
        "id": "deepseek-ai-DeepSeek-V4-Flash-8bit",
        "displayName": "Deepseek Ai Deepseek V 4 Flash (MLX)",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "omlx/Qwen3.6-27B-oQ4e-mtp": {
        "sourceOrder": 84,
        "provider": "omlx",
        "id": "Qwen3.6-27B-oQ4e-mtp",
        "displayName": "Qwen 3.6 27B Oq 4E Mtp (MLX)",
        "maxOutputTokens": 128000,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "omlx/Qwen3.6-27B-oQ8-mtp": {
        "sourceOrder": 85,
        "provider": "omlx",
        "id": "Qwen3.6-27B-oQ8-mtp",
        "displayName": "Qwen 3.6 27B Oq 8 Mtp (MLX)",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "omlx/Qwen3.6-35B-A3B-oQ4-mtp": {
        "sourceOrder": 86,
        "provider": "omlx",
        "id": "Qwen3.6-35B-A3B-oQ4-mtp",
        "displayName": "Qwen 3.6 35B A 3B Oq 4 Mtp (MLX)",
        "maxOutputTokens": 128000,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "llama-cpp-local/Bonsai-8B": {
        "sourceOrder": 87,
        "provider": "llama-cpp-local",
        "id": "Bonsai-8B",
        "displayName": "Bonsai 8B",
        "maxOutputTokens": 128000,
        "selectors": {},
        "contextLimit": 131072,
        "outputLimit": 65536
      },
      "llama-cpp-local/cohere-transcribe-03-2026": {
        "sourceOrder": 88,
        "provider": "llama-cpp-local",
        "id": "cohere-transcribe-03-2026",
        "displayName": "Cohere Transcribe 03",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "llama-cpp-local/mlx-community/deepseek-ai-DeepSeek-V4-Flash-8bit": {
        "sourceOrder": 89,
        "provider": "llama-cpp-local",
        "id": "mlx-community/deepseek-ai-DeepSeek-V4-Flash-8bit",
        "displayName": "Deepseek Ai Deepseek V 4 Flash (MLX)",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "llama-cpp-local/GLM-4.7-Flash": {
        "sourceOrder": 90,
        "provider": "llama-cpp-local",
        "id": "GLM-4.7-Flash",
        "displayName": "GLM 4.7 Flash",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 202752,
        "outputLimit": 65536
      },
      "llama-cpp-local/GLM-5.2": {
        "sourceOrder": 91,
        "provider": "llama-cpp-local",
        "id": "GLM-5.2",
        "displayName": "GLM 5.2",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 200000,
        "outputLimit": 65536
      },
      "llama-cpp-local/gpt-oss-120b": {
        "sourceOrder": 92,
        "provider": "llama-cpp-local",
        "id": "gpt-oss-120b",
        "displayName": "GPT-OSS 120B",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 131072,
        "outputLimit": 65536
      },
      "llama-cpp-local/gpt-oss-20b": {
        "sourceOrder": 93,
        "provider": "llama-cpp-local",
        "id": "gpt-oss-20b",
        "displayName": "GPT-OSS 20B",
        "maxOutputTokens": 128000,
        "selectors": {},
        "contextLimit": 131072,
        "outputLimit": 65536
      },
      "llama-cpp-local/gpt-oss-safeguard-20b": {
        "sourceOrder": 94,
        "provider": "llama-cpp-local",
        "id": "gpt-oss-safeguard-20b",
        "displayName": "GPT-OSS Safeguard 20B",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 131072,
        "outputLimit": 65536
      },
      "llama-cpp-local/granite-speech-4.1-2b": {
        "sourceOrder": 95,
        "provider": "llama-cpp-local",
        "id": "granite-speech-4.1-2b",
        "displayName": "Granite Speech 4.1 2B",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "llama-cpp-local/Huihui-Qwable-3.6-27b-abliterated-MTP": {
        "sourceOrder": 96,
        "provider": "llama-cpp-local",
        "id": "Huihui-Qwable-3.6-27b-abliterated-MTP",
        "displayName": "Huihui Qwable 3.6 27B Abliterated Mtp",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "llama-cpp-local/LFM2.5-350M": {
        "sourceOrder": 97,
        "provider": "llama-cpp-local",
        "id": "LFM2.5-350M",
        "displayName": "LFM 2.5 350M",
        "maxOutputTokens": 128000,
        "selectors": {},
        "contextLimit": 131072,
        "outputLimit": 65536
      },
      "llama-cpp-local/GreenBitAI/Llama-2-13B-layer-mix-bpw-2.2-mlx": {
        "sourceOrder": 98,
        "provider": "llama-cpp-local",
        "id": "GreenBitAI/Llama-2-13B-layer-mix-bpw-2.2-mlx",
        "displayName": "Llama 2 13B Layer Mix Bpw 2.2 (MLX)",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "llama-cpp-local/GreenBitAI/Llama-2-13B-layer-mix-bpw-2.5-mlx": {
        "sourceOrder": 99,
        "provider": "llama-cpp-local",
        "id": "GreenBitAI/Llama-2-13B-layer-mix-bpw-2.5-mlx",
        "displayName": "Llama 2 13B Layer Mix Bpw 2.5 (MLX)",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "llama-cpp-local/GreenBitAI/Llama-2-13B-layer-mix-bpw-3.0-mlx": {
        "sourceOrder": 100,
        "provider": "llama-cpp-local",
        "id": "GreenBitAI/Llama-2-13B-layer-mix-bpw-3.0-mlx",
        "displayName": "Llama 2 13B Layer Mix Bpw 3.0 (MLX)",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "llama-cpp-local/Meta-Llama-3.1-8B": {
        "sourceOrder": 101,
        "provider": "llama-cpp-local",
        "id": "Meta-Llama-3.1-8B",
        "displayName": "Meta Llama 3.1 8B",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "llama-cpp-local/Nemotron-3-Nano-30B-A3B": {
        "sourceOrder": 102,
        "provider": "llama-cpp-local",
        "id": "Nemotron-3-Nano-30B-A3B",
        "displayName": "Nemotron 3 Nano 30B",
        "maxOutputTokens": 128000,
        "selectors": {},
        "contextLimit": 1048576,
        "outputLimit": 65536
      },
      "llama-cpp-local/Nemotron-Cascade-2-30B-A3B": {
        "sourceOrder": 103,
        "provider": "llama-cpp-local",
        "id": "Nemotron-Cascade-2-30B-A3B",
        "displayName": "Nemotron Cascade 2 30B",
        "maxOutputTokens": 128000,
        "selectors": {},
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "llama-cpp-local/NVIDIA-Nemotron-3-Super-120B-A12B": {
        "sourceOrder": 104,
        "provider": "llama-cpp-local",
        "id": "NVIDIA-Nemotron-3-Super-120B-A12B",
        "displayName": "NVIDIA Nemotron 3 Super 120B",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 1048576,
        "outputLimit": 65536
      },
      "llama-cpp-local/Phi-4-reasoning-plus": {
        "sourceOrder": 105,
        "provider": "llama-cpp-local",
        "id": "Phi-4-reasoning-plus",
        "displayName": "Phi 4 Reasoning Plus",
        "maxOutputTokens": 128000,
        "selectors": {},
        "contextLimit": 32768,
        "outputLimit": 65536
      },
      "llama-cpp-local/Qwopus3.5-27B-v3": {
        "sourceOrder": 106,
        "provider": "llama-cpp-local",
        "id": "Qwopus3.5-27B-v3",
        "displayName": "Qwopus 3.5 27B V 3",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "llama-cpp-local/SERA-32B": {
        "sourceOrder": 107,
        "provider": "llama-cpp-local",
        "id": "SERA-32B",
        "displayName": "SERA 32B",
        "maxOutputTokens": 128000,
        "selectors": {},
        "contextLimit": 40960,
        "outputLimit": 65536
      },
      "llama-cpp-local/thesven": {
        "sourceOrder": 108,
        "provider": "llama-cpp-local",
        "id": "thesven",
        "displayName": "Thesven",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "llama-cpp-local/atorsvn/TinyLlama-1.1B-Chat-v0.1-gptq-4bit": {
        "sourceOrder": 109,
        "provider": "llama-cpp-local",
        "id": "atorsvn/TinyLlama-1.1B-Chat-v0.1-gptq-4bit",
        "displayName": "Tinyllama 1.1B Chat V 0.1 Gptq (MLX)",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      },
      "llama-cpp-local/atorsvn/TinyLlama-1.1B-step-50K-105b-gptq-4bit": {
        "sourceOrder": 110,
        "provider": "llama-cpp-local",
        "id": "atorsvn/TinyLlama-1.1B-step-50K-105b-gptq-4bit",
        "displayName": "Tinyllama 1.1B Step 50K 105B Gptq (MLX)",
        "maxOutputTokens": 128000,
        "selectors": {
          "hosts": [
            "hera"
          ]
        },
        "contextLimit": 262144,
        "outputLimit": 65536
      }
    }  '';

  defaultModel = {
    provider = "litellm";
    model = "hera/omlx/Qwen3.6-27B-oQ4e-mtp";
  };
in
{
  inherit providers models;

  profileDefaults = {
    "clio-opencode" = defaultModel;
    "hera-opencode" = defaultModel;
    "shared-work-opencode-positron" = defaultModel;
  };

  syncInputs = defaultModel // {
    chatUrl = "https://litellm.vulcan.lan/v1/chat/completions";
  };
}

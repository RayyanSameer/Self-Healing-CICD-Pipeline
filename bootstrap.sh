#!/usr/bin/env bash
set -euo pipefail
cd ~
[ -d Self-Healing-CICD-Pipeline ] || git clone https://github.com/RayyanSameer/Self-Healing-CICD-Pipeline.git
cd Self-Healing-CICD-Pipeline/basic_app
python3 -m venv venv
venv/bin/pip install -r requirements.txt
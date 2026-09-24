from flask import Flask, jsonify
import os \

app = Flask(__name__)


@app.route('/')
def index():
    return jsonify({"message": "hello world"})

@app.route('/health')
def health():
    if os.environ.get('APP_ENV') != 'production':
        return jsonify({"status": "unhealthy", "reason": "env not set"}), 500
    return jsonify({"status": "healthy"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)  # nosec B104 - required for Docker container networking
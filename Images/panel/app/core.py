from flask import Flask, jsonify, request
from tools import run

VERSION = "0.1.0"
app = Flask(__name__)

@app.get("/health")
def health():
    return jsonify(status="ok", version=VERSION)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=1919, debug=True)

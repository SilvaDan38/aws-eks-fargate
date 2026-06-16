import ddtrace
ddtrace.patch_all()

import logging
import json
from flask import Flask, jsonify
import time, random
from ddtrace import tracer

# Logging com trace ID injection para correlação no Datadog
FORMAT = ('%(asctime)s %(levelname)s [%(name)s] [%(filename)s:%(lineno)d] '
          '[dd.service=%(dd.service)s dd.env=%(dd.env)s dd.version=%(dd.version)s '
          'dd.trace_id=%(dd.trace_id)s dd.span_id=%(dd.span_id)s] '
          '- %(message)s')
logging.basicConfig(format=FORMAT, level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

@app.route("/")
def index():
    logger.info("GET /")
    return jsonify(status="ok", service="python-app")

@app.route("/ping")
def ping():
    logger.info("GET /ping")
    return jsonify(message="pong")

@app.route("/work")
def work():
    with tracer.trace("work.simulate"):
        duration = random.uniform(0.01, 0.1)
        time.sleep(duration)
        logger.info("work completed", extra={"duration_ms": round(duration * 1000, 2)})
    return jsonify(result="done")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

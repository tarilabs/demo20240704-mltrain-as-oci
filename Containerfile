FROM python:3.10-bullseye

COPY requirements.txt requirements.txt
COPY train_model.py train_model.py
COPY report_sha.py report_sha.py
COPY thirdparty/ thirdparty/

RUN pip install -r requirements.txt
RUN pip install thirdparty/oml-0.1.0-py3-none-any.whl

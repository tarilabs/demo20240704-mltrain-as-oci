FROM python:3.10-bullseye

RUN groupadd -r oml && useradd -m -r -g oml oml
WORKDIR /app

COPY requirements.txt requirements.txt
COPY train_model.py train_model.py
COPY report_sha.py report_sha.py
COPY thirdparty/ thirdparty/

RUN chown -R oml:oml /app
USER oml
RUN mkdir /home/oml/.docker

RUN pip install -r requirements.txt
RUN pip install thirdparty/oml-0.1.0-py3-none-any.whl

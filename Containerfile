FROM python:3.10-bullseye

# TODO: Install some helpful utilities to inspect OCI images. Ideally, use proper code in
# python (for example) to do this. For the sake of a POC, I can move faster with some dirty
# bash.
RUN apt-get update && apt-get -y install skopeo && apt-get clean autoclean && \
    apt-get autoremove --yes && rm -rf /var/lib/{apt,dpkg,cache,log}/

RUN wget "https://github.com/sigstore/cosign/releases/download/v2.4.1/cosign-linux-amd64" 
RUN mv cosign-linux-amd64 /usr/local/bin/cosign
RUN chmod +x /usr/local/bin/cosign

RUN skopeo --version
RUN cosign version

WORKDIR /app

COPY requirements.txt requirements.txt

RUN pip install -r requirements.txt

COPY train_model.py train_model.py

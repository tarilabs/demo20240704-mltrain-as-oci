import argparse
import joblib
import oras.provider
import oras.version
from sklearn.svm import SVC
from sklearn.metrics import accuracy_score
import oras.client
from omlmd.helpers import Helper
from omlmd.provider import OMLMDRegistry

def main(image, dataset, image_url, image_digest):
    print(f"Pulling {dataset}")
    client = oras.client.OrasClient()
    client.pull(target=dataset, outdir=".")

    print("Training dataset loading...")
    X_train = open_as_joblib("X_train")
    X_test = open_as_joblib("X_test")
    y_train = open_as_joblib("y_train")
    y_test = open_as_joblib("y_test")
    print("Training ML model...")
    svc_linear = SVC(kernel="linear", probability=True)
    svc_linear.fit(X_train, y_train)

    print("Model trained.")
    y_pred = svc_linear.predict(X_test)
    accuracy_value = accuracy_score(y_test, y_pred)
    save_as_joblib("model", svc_linear)
    print("accuracy:", accuracy_value)

    dry_run(0, svc_linear, X_test, y_test) # lame, but okay for this demo
    dry_run(1, svc_linear, X_test, y_test)
    dry_run(4, svc_linear, X_test, y_test)

    print(f"Pushing OCI Artifact of the ML model to {image}")
    omlmd = Helper(OMLMDRegistry())
    r = omlmd.push(image, "model.joblib", name="Model Example", author="John Doe", license="Apache-2.0", accuracy=accuracy_value)
    sha = r.headers["Docker-Content-Digest"]
    print("digest:", sha)

    with open(image_url, "w") as f:
        f.write(image)
    with open(image_digest, "w") as f:
        f.write(sha)


def dry_run(idx: int, model, X_test, y_test):
    in_idx = X_test[idx].reshape(1, -1)
    pred_idx = model.predict(in_idx)
    test_idx = y_test[idx]
    print(idx, in_idx, pred_idx, test_idx)
    if not pred_idx[0] == test_idx:
        raise RuntimeError("unexpected drift")


def open_as_joblib(filename: str):
    with open(filename+".joblib", 'rb') as fi:
        return joblib.load(fi)


def save_as_joblib(filename: str, data):
    with open(filename+".joblib", 'wb') as fo:
        joblib.dump(data, fo)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True)
    parser.add_argument("--dataset", required=True)
    parser.add_argument("--results-image-url-path", required=True)
    parser.add_argument("--results-image-digest-path", required=True)
    args = parser.parse_args()

    main(image=args.image, dataset=args.dataset, image_url=args.results_image_url_path, image_digest=args.results_image_digest_path)

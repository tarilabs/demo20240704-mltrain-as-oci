import joblib
from sklearn import datasets
from sklearn.model_selection import train_test_split


def main():
    X, y = datasets.load_iris(return_X_y=True)
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size = 0.3, random_state = 1, stratify = y)
    save_as_joblib("X_train", X_train)
    save_as_joblib("X_test", X_test)
    save_as_joblib("y_train", y_train)
    save_as_joblib("y_test", y_test)


def save_as_joblib(filename: str, data):
    with open(filename+".joblib", 'wb') as fo:  
        joblib.dump(data, fo)


if __name__ == "__main__":
    main()

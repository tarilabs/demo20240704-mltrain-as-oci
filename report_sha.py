import oras.client
import oras.provider
from oras.provider import container_type
import jsonschema
from typing import Callable, Generator, List, Optional, Tuple, Union
import oras.decorator as decorator

class CustomRegistry(oras.provider.Registry):
    @decorator.ensure_container
    def get_sha(
        self,
        container: container_type,
        allowed_media_type: Optional[list] = None,
        refresh_headers: bool = True,
    ) -> dict:
        if not allowed_media_type:
            allowed_media_type = [oras.defaults.default_manifest_media_type]
        headers = {"Accept": ";".join(allowed_media_type)}

        if not refresh_headers:
            headers.update(self.headers)

        get_manifest = f"{self.prefix}://{container.manifest_url()}"  # type: ignore
        response = self.do_request(get_manifest, "GET", headers=headers)
        self._check_200_response(response)
        return response.headers["Docker-Content-Digest"]

def main():
    reg = CustomRegistry()
    print(reg.get_sha("quay.io/mmortari/ml-iris:v1"))


if __name__ == "__main__":
    main()
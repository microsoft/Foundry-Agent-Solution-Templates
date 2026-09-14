from provision import SearchClient, ownership_path, require
from ownership import cleanup_targets

client = SearchClient(require("AZURE_SEARCH_ENDPOINT"))
state_path = ownership_path()
targets = cleanup_targets(state_path, client.endpoint)
for kind, name in targets:
    client.request("DELETE", f"{kind}/{name}", expected=(200, 204, 404))
# Retain the journal so a later Toolbox/connection deletion failure can be
# retried safely; Search DELETE already treats missing objects as success.
print("Template-owned Search objects removed.")

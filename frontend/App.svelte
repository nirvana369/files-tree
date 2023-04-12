<script>
  /*
   * Connect2ic provides essential utilities for IC app development
   */
  import { createClient } from "@connect2ic/core"
  import { defaultProviders } from "@connect2ic/core/providers"
  import { Connect2ICProvider } from "@connect2ic/svelte"
  import "@connect2ic/core/style.css"
  /*
   * Import canister definitions like this:
   */
  import * as registry from "../.dfx/local/canisters/registry"
  import * as storage from "../.dfx/local/canisters/storage"
  /*
   * Some examples to get you started
   */
  import FileTreeExplorer from "./components/FileTreeExplorer.svelte"
//   import "carbon-components-svelte/css/g80.css";
  import "carbon-components-svelte/css/g90.css";
//   import "carbon-components-svelte/css/g100.css";

  const client = createClient({
    canisters: {
      registry,
      storage
    },
    providers: defaultProviders,
    globalProviderConfig: {
      dev: import.meta.env.DEV,
    },
  })
</script>

<Connect2ICProvider client={client}>
  <div class="App">
    <FileTreeExplorer />  
  </div>
</Connect2ICProvider>

<style global>
    
</style>

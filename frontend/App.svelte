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
  import logo from "./assets/IC_logo_horizontal.svg"
  import FileTreeExplorer from "./components/FileTreeExplorer.svelte"
//   import "carbon-components-svelte/css/g80.css";
  import "carbon-components-svelte/css/g90.css";
//   import "carbon-components-svelte/css/g100.css";
  import { Content, Grid, Row, Column } from "carbon-components-svelte";
  import { isDebug } from "./stores";

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

  const queryString = window.location.search;
  const urlParams = new URLSearchParams(queryString);
  const product = urlParams.get('is_debug');
  $isDebug = product === "true";
</script>

<Connect2ICProvider client={client}>
  <div class="App">
    <FileTreeExplorer />  
  </div>
</Connect2ICProvider>
<Content class="content flex column items-stretch">

  <footer class="flex-constant">
      <div class="footer-content">
        <div class="flex-grow">
          <Grid>
              <Row>
                  
                  <Column sm={1} md={1} lg={6}><p></p></Column>
                  <Column sm={1} md={1} lg={4}>
                    
                  </Column>
                  <Column sm={1} md={1} lg={3}></Column>
              </Row>
          </Grid>
      </div>
        
        <ul class="socials">
          <!-- <li><a href="#"><i class="fa fa-facebook"></i></a></li>
          <li><a href="#"><i class="fa fa-twitter"></i></a></li>
          <li><a href="#"><i class="fa fa-google-plus"></i></a></li>
          <li><a href="#"><i class="fa fa-youtube"></i></a></li>
          <li><a href="#"><i class="fa fa-linkedin-square"></i></a></li> -->
          <li><div class="mediaLinks_IgUQ"><a href="https://github.com/nirvana369/files-tree" target="_blank" rel="noopener noreferrer" aria-label="Go to GitHub"><img src="data:image/svg+xml,%3Csvg width='24px' height='24px' viewBox='0 0 64 64' id='i-github' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath stroke-width='0' fill='white' d='M32 0 C14 0 0 14 0 32 0 53 19 62 22 62 24 62 24 61 24 60 L24 55 C17 57 14 53 13 50 13 50 13 49 11 47 10 46 6 44 10 44 13 44 15 48 15 48 18 52 22 51 24 50 24 48 26 46 26 46 18 45 12 42 12 31 12 27 13 24 15 22 15 22 13 18 15 13 15 13 20 13 24 17 27 15 37 15 40 17 44 13 49 13 49 13 51 20 49 22 49 22 51 24 52 27 52 31 52 42 45 45 38 46 39 47 40 49 40 52 L40 60 C40 61 40 62 42 62 45 62 64 53 64 32 64 14 50 0 32 0 Z' /%3E%3C/svg%3E" alt=""></a></div></li>
        </ul>
      </div>
      <!-- <div class="footer-bottom">
        <p>Copyright &copy <span id="year"></span> <a href="https://github.com/nirvana369">@nirvana369</a> </p>
        <div class="footer-menu">
          <ul class="f-menu">
            <li><a href="https://github.com/nirvana369">Home</a></li>
            <li><a href="https://github.com/nirvana369">About</a></li>
            <li><a href="https://github.com/nirvana369">Contact</a></li>
            <li><a href="https://github.com/nirvana369">Blog</a></li>
          </ul>
        </div>
      </div> -->
  </footer>
</Content>

<style>
  :global(.flex) { display: flex; }
  :global(.flex.column) { flex-direction: column; }
  :global(.flex.items-stretch) { align-items: stretch; }
  :global(.flex-grow) { 
      flex-grow: 1;
      flex-shrink: 0;
  }
  :global(.flex-constant) { 
      flex-grow: 0;
      flex-shrink: 0;
  }
  :global(.content) {
      padding: 0;
      min-height: calc(30vh - 3rem); /* 3rem = header */
  }
  * {
  margin: 0;

  padding: 0;

  box-sizing: border-box;
}

.footer-content {
  display: flex;

  align-items: center;

  justify-content: center;

  flex-direction: column;

  text-align: center;
}

.footer-content h3 {
  font-size: 2.1rem;

  font-weight: 500;

  text-transform: capitalize;

  line-height: 3rem;
}

.footer-content p {
  max-width: 500px;

  margin: 50px auto;

  line-height: 28px;

  font-size: 14px;

  color: #cacdd2;
}

.socials {
  list-style: none;

  display: flex;

  align-items: center;

  justify-content: center;

  margin: 1rem 0 3rem 0;
}

.socials li {
  margin: 0 10px;
}

.socials a {
  text-decoration: none;

  color: #fff;

  padding: 5px;
}

.socials a i {
  font-size: 1.1rem;

  width: 20px;

  transition: color 0.4s ease;
}

.socials a:hover i {
  color: aqua;
}

.footer-bottom {
  background: #000;

  width: 100vw;

  padding: 20px;

  padding-bottom: 40px;

  text-align: center;
}

.footer-bottom p {
  float: left;

  font-size: 14px;

  word-spacing: 2px;
}

.footer-bottom p a {
  color: #ccc;

  font-size: 16px;

  text-decoration: none;
}

.footer-bottom span {
  text-transform: uppercase;
}

.footer-menu {
  float: right;
}

.footer-menu ul {
  display: flex;
}

.footer-menu ul li {
  padding-right: 10px;

  display: block;
}

.footer-menu ul li a {
  color: #cfd2d6;

  text-decoration: none;
}

.footer-menu ul li a:hover {
  color: #27bcda;
}

@media (max-width: 500px) {
  .footer-bottom p {
    float: none;
  }

  .footer-menu ul {
    display: flex;

    margin-top: 10px;

    margin-bottom: 20px;

    text-align: center;
  }
}

</style>

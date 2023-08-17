var Module;
Module['arguments'] = [];
FS.mkdir('/appdata');
FS.mount(IDBFS,{},'/appdata');

Module['postRun'].push(function() {
  var argv = []
  var req
  var url

  var metatags = document.getElementsByTagName('meta');

  for (var mt = 0; mt < metatags.length; mt++) { 
    if (metatags[mt].getAttribute("name") === "file") {
      url = metatags[mt].getAttribute("content");
    }
  }

  if (!url && typeof window === "object") {
    argv = window.location.search.substr(1).trim().split('&');
    if (!argv[0])
      argv = [];
    url = argv[0];
  }
  if (!url)
    url = 'edit'

  req = new XMLHttpRequest();
  req.open("GET", url+'?'+(Math.random()*10000000), true);
  req.responseType = "arraybuffer";
  console.log("Get: ", url);

  req.onload = function() {
    var basename = function(path) {
      parts = path.split( '/' );
      return parts[parts.length - 1];
    }
    var data = req.response;
    console.log("Data loaded...");
    FS.syncfs(true, function (error) {
      if (error) {
        console.log("Error while syncing: ", error);
      }
      url = basename(url);
      console.log("Writing: ", url);
      FS.writeFile(url, new Int8Array(data), { encoding: 'binary' }, "w");
      window.onclick = function(){ window.focus() };
      console.log("Running...");
//      Module['arguments'].push("-s");
      Module['arguments'].push(url);
      callMain(Module['arguments']);
    });
  }
  req.send(null);
});

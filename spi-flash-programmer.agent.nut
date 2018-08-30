// Agent source code goes here

const chunk = 16384;
offset <- 0;
size <- 0;
source <- "";

bufferoffset <- 0;
buffersize <- 0;
buffer <- null;
percent <- 0;

function buffered_fetch(address) {
    // Can we satisfy at least 4k from the buffer we have?
    if (address >= bufferoffset && (address+4096)<=(bufferoffset+buffersize)) {
        // Trim to available size
        local chunksize = buffersize - (address-bufferoffset);
        if (chunksize > chunk) chunksize = chunk;
        
        device.send("flash", {"address":address, "data":buffer.slice(address-bufferoffset, address-bufferoffset+chunksize), "percent":percent});
        return;
    }
    
    // Try to fetch 256kB at this location
    bufferoffset = address;
    percent = (100*address/size)
    local r = http.get(source, {"Range":format("bytes=%d-%d", bufferoffset, bufferoffset+(256*1024)-1)}).sendsync();
    if (r.statuscode >= 200 && r.statuscode < 300) {
        server.log("Fetched "+r.body.len()+" bytes at "+address+" ("+(100*address/size)+"%)");
        
        buffer = r.body;
        buffersize = buffer.len();
        r.body=null;
        
        // Re-fetch from cache
        buffered_fetch(address);
    } else {
        server.log("Fetch failed, status "+r.statuscode);
    }
}

function fetchwrite(address) {
    local r = http.get(source, {"Range":format("bytes=%d-%d", address, address+chunk-1)}).sendsync();
    if (r.statuscode >= 200 && r.statuscode < 300) {
        server.log("Fetched "+r.body.len()+" bytes at "+address);
        device.send("flash", {"address":address, "data":r.body});
    }
}

// Gets passed size of last fetch
device.on("ack", function(v) {
    //server.log("got ack");
    offset += v;
    if (offset < size) buffered_fetch(offset);
});

device.on("start", function(v) {
    // Note the size
    source = v.path;
    size = v.trim;
    offset = 0;
    
    server.log("Fetching image from "+source);
    server.log(format("Trimming to 0x%x bytes", size));

    // Start the flash
    buffered_fetch(0);
});


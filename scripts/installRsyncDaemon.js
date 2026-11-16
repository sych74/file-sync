// Passes to the installLsync action of every node:
// @settingsPath - the first sync path, used by installLsync of older manifests
// @syncPaths - comma-separated sync paths relative to lsyncdPath, "/" is lsyncdPath itself
// @syncTargets - comma-separated hosts to sync to: the mirror node and the optional second environment
// @delay - sync delay in seconds
// @secondEnvAddress
// @syncPassword

var NODE_GROUP_STORAGE = "storage",
    PROCEDURE_PROCESS_NODE = "installLsync",
    APPID = getParam("TARGET_APPID"),
    SESSION = getParam("session"),
    USER = "jelastic",
    syncPassword = "${settings.password}",
    secondAddress = "${settings.address}",
    rawPaths = "${settings.path}",
    delay = "${settings.delay}",
    isStorageNode = false,
    envLsyncdNodes = [],
    aCpItemEnvs = [],
    resp,
    mirrorServerIp,
    callArgs = [],
    lsyncdPath,
    parsed,
    syncPaths,
    nodes,
    env,
    i,
    j,
    n;

if (syncPassword.indexOf("{settings.password}") != -1) {
    syncPassword = "defaultPassword";
}

if (secondAddress.indexOf("{settings.address}") != -1) {
    secondAddress = "";
}

if (rawPaths.indexOf("{settings.path}") != -1) {
    rawPaths = "";
}

if (!/^\d+$/.test(delay)) {
    delay = "10";
}

// Parses a comma-separated list of sync paths into paths relative to basePath
// without leading and trailing slashes; "" stands for basePath itself.
// Returns { paths: [...] } or { error: "..." }.
function parseSyncPaths(raw, basePath) {
    var base = String(basePath).replace(/\/+$/, ""),
        items = String(raw).split(","),
        paths = [],
        seen = {},
        p, a, b, i, j;

    for (i = 0; i < items.length; i += 1) {
        p = String(items[i]).replace(/^\s+|\s+$/g, "");
        if (!p) continue;

        if (p == base || p.indexOf(base + "/") == 0) {
            p = p.substring(base.length);
        }
        p = p.replace(/\/+/g, "/").replace(/^\/|\/$/g, "");

        // The paths are put into shell commands and configuration files.
        if (/[`$\\"'|;&<>\r\n]/.test(p) || /(^|\/)\.\.?(\/|$)/.test(p)) {
            return { error: "Invalid sync path: " + items[i] };
        }

        if (!seen[p]) {
            seen[p] = true;
            paths.push(p);
        }
    }

    if (!paths.length) {
        paths.push("");
    }

    // A nested path would be synchronized twice by different sync blocks.
    for (i = 0; i < paths.length; i += 1) {
        for (j = i + 1; j < paths.length; j += 1) {
            a = paths[i] + "/";
            b = paths[j] + "/";

            if (a == "/" || b == "/" || a.indexOf(b) == 0 || b.indexOf(a) == 0) {
                return { error: "Sync paths must not be nested: " + (paths[i] || "/") + ", " + (paths[j] || "/") };
            }
        }
    }

    return { paths: paths };
}

resp = jelastic.environment.control.GetEnvInfo(APPID, SESSION);

if (resp.result != 0) return resp;

nodes = resp.nodes;

for (i = 0, n = nodes.length; i < n; i += 1) {
    if ("${targetNodes.nodeGroup}" == nodes[i].nodeGroup) {
        isStorageNode = !!(NODE_GROUP_STORAGE == nodes[i].nodeType);
        envLsyncdNodes.push(nodes[i]);
    }
}

if (envLsyncdNodes[0].type == "DOCKERIZED") {
    if (!envLsyncdNodes[0].engines) {
        aCpItemEnvs = envLsyncdNodes[0].customitem.dockerManifest.env;

        for (j = 0; aCpItemEnvs[j]; j += 1) {

            if (/^WEBROOT=/.test(aCpItemEnvs[j])) {
                lsyncdPath = aCpItemEnvs[j].replace('WEBROOT=', '') + '/';
                break;
            }
        }
    }
}

if (!lsyncdPath) {
    lsyncdPath = isStorageNode ? "/data/" : "${SERVER_WEBROOT}/";
}

parsed = parseSyncPaths(rawPaths, lsyncdPath);

if (parsed.error) {
    return { result: 99, error: parsed.error };
}

// Action parameters are never left empty: "/" stands for lsyncdPath itself.
syncPaths = parsed.paths.map(function (p) { return p || "/"; }).join(",");

for (i = 0, n = envLsyncdNodes.length; i < n; i += 1) {
    mirrorServerIp = envLsyncdNodes[(i + 1) === envLsyncdNodes.length ? 0 : i + 1].address;

    callArgs.push({
        action : PROCEDURE_PROCESS_NODE,
        params : {
            nodeId : envLsyncdNodes[i].id,
            mirrorServerIp : mirrorServerIp,
            settingsPath : parsed.paths[0] || "/",
            syncPaths : syncPaths,
            syncTargets : secondAddress ? mirrorServerIp + "," + secondAddress : mirrorServerIp,
            delay : delay,
            secondEnvAddress : secondAddress,
            syncPassword : syncPassword,
            lsyncdPath : lsyncdPath,
            user : USER
        }
    });
}

return {
    result : 0,
    onAfterReturn : {
        call : callArgs
    }
};

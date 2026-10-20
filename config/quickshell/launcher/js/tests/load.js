// Test helper: loads QML-style .pragma library files into a vm context.
const fs = require("fs");
const path = require("path");
const vm = require("vm");

function load(file) {
    const dir = path.join(__dirname, "..");
    const sandbox = { Math, Object, Array, String, JSON };
    let src = fs.readFileSync(path.join(dir, file), "utf8");
    src = src.replace(/^\.pragma.*$/m, "");
    src = src.replace(/^\.import\s+"([^"]+)"\s+as\s+(\w+)\s*$/gm, (_, f, name) => {
        sandbox[name] = load(f);
        return "";
    });
    vm.createContext(sandbox);
    vm.runInContext(src, sandbox);
    return sandbox;
}
module.exports = { load };

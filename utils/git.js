const util = require('util');
const { exec } = require('child_process');

const execPromise = util.promisify(exec);

module.exports = { execPromise };

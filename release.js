#!/usr/bin/env node

const { exec } = require('child_process');
const path = require('path');
const crypto = require('crypto');
const { createReadStream, createWriteStream } = require('fs');
const { writeFile } = require('fs/promises');
const { Readable, Transform } = require('stream');
const { pipeline } = require('stream/promises');

const runCommand = (cmd, context) => {
	return new Promise((resolve) => {
		exec(cmd, (error, stdout, stderr) => {
			const exitCode = error ? error.code : 0;
			
			resolve({
				context,
				command: cmd,
				stdout: stdout.trim(),
				stderr: stderr.trim(),
				exitCode
			});
		});
	});
};

const report = results => {
	results.forEach(result => {
		console.log(`------------- Architecture (${result.context.docker}, ${result.context.guix}) -------------`);
		console.log(`STDOUT:	${result.stdout}`);
		console.log(`STDERR:	${result.stderr || '(none)'}`);
		console.log(`EXIT CODE: ${result.exitCode}`);
		console.log('----------------------------------------------------\n');
	});
};

const sha256 = (filePath, fn, context) => {
	return new Promise((resolve, reject) => {
		const hash = crypto.createHash('sha256');
		const stream = createReadStream(filePath);

		stream.on('error', err => reject(err));
		stream.on('data', chunk => hash.update(chunk));
		stream.on('end', () => resolve(fn(hash.digest('hex'), context)));
	});
};

const latestRelease = async () => {
	const latestResponse = await fetch('https://github.com/metacall/guix-binary/releases/latest', {
		method: 'HEAD',
		redirect: 'follow'
	});

	return latestResponse.url.replace('/releases/tag/', '/releases/download/');
};

const fetchBuildJson = async downloadBaseUrl => {
	const metadataUrl = `${downloadBaseUrl}/build.json`;
	const metadataResponse = await fetch(metadataUrl);
	
	if (!metadataResponse.ok) {
		throw new Error(`Failed to fetch metadata from ${metadataUrl}`);
	}

	return await metadataResponse.json();
};

const fetchFile = async (outputDir, url, fileName, transform) => {
	const channelsPath = path.join(outputDir, fileName);

	const response = await fetch(url);

	if (!response.ok) {
		throw new Error(`Failed to fetch ${fileName} from ${url}: ${response.status} ${response.statusText}`);
	}

	const streams = [
		Readable.fromWeb(response.body),
		transform,
		createWriteStream(channelsPath)
	].filter(Boolean);

    await pipeline(...streams);
};

const fetchChannels = async (outputDir) => fetchFile(
	outputDir,
	'https://ci.guix.gnu.org/eval/latest/channels.scm?spec=guix',
	'channels.scm',
	new Transform({
		transform: (chunk, encoding, callback) => {
			// Replace the URL of the repository by Codeberg
			// Codeberg is faster than Savanah and Guix
			// will be migrated eventually into it
			const content = chunk.toString().replaceAll(
				'https://git.guix.gnu.org/guix.git',
				'https://codeberg.org/guix/guix.git'
			);

			// Push the modified chunk back into the stream
			callback(null, content);
		}
	})
);

const fetchInstall = async (outputDir) => fetchFile(
	outputDir,
	'https://guix.gnu.org/install.sh',
	'install.sh'
);

const release = async () => {
	const architectures = [
		{ docker: 'linux/amd64', guix: 'x86_64-linux' },
		{ docker: 'linux/386', guix: 'i686-linux' },
		{ docker: 'linux/arm/v7', guix: 'armhf-linux' },
		{ docker: 'linux/arm64/v8', guix: 'aarch64-linux' },
		{ docker: 'linux/ppc64le', guix: 'powerpc64le-linux' },
		{ docker: 'linux/riscv64', guix: 'riscv64-linux' }
	];

	// Install QEMU for executing the images in multiple architectures
	const dependency = await runCommand('docker run --rm --privileged multiarch/qemu-user-static --reset -p yes');

	if (dependency.exitCode != 0) {
		throw Error(`Failed to install QEMU multiarch:
			${dependency.stdout}
			${dependency.stderr}
		`);
	}

	// Define constants
	const version = new Date().toISOString().slice(0, 10).replace(/-/g, '');
	const hostOutput = path.resolve(__dirname, 'out');
	const containerOutput = '/output';
	const hostScripts = path.resolve(__dirname, 'scripts');
	const containerScripts = '/scripts';

	// Define tasks for releasing for each architecture
	const tasks = architectures.map(arch => {
		const dockerCmd = `docker run --rm --privileged \
			-v ${hostOutput}:${containerOutput} \
			-v ${hostScripts}:${containerScripts} \
			--platform ${arch.docker} \
			-t metacall/guix \
			${containerScripts}/release.sh "${arch.guix}" "${containerOutput}" "${version}"`;

		return runCommand(dockerCmd, architectures);
	});

	// Execute the tasks and print the results
	const results = await Promise.all(tasks);
	const errors = results.filter(result => result.exitCode != 0);

	if (errors.length > 0) {
		console.log('ERROR: While processing the following architectures:')
		report(errors);
		process.exit(1);
	}

	report(results);

	// Get latest release download base URL
	const latestReleaseUrl = await latestRelease();

	// Get the latest build.json
	const latestJson = await fetchBuildJson(latestReleaseUrl);

	// Define resource name
	const resourceName = (resource, version, arch) => `guix-${resource}-${version}.${arch}.tar.xz`;

	// Get the SHA256 of all files
	const computeSha256 = async resource => {
		return await Promise.all(architectures.map(arch => {
			const filePath = path.join(hostOutput, resourceName(resource, version, arch.guix));

			return sha256(filePath, (sha256, arch) => {
				return {
					arch,
					filePath,
					sha256
				};
			}, arch.guix);
		}));
	};

	const binaries = await computeSha256('binary');
	const caches = await computeSha256('cache');

	// Generate build.json with all the information and the files to release
	const newJson = {};
	const releaseFiles = [];

	for (const binary of binaries) {
		newJson[binary.arch] = {
			url: '',
			sha256: binary.sha256,
			cache: {
				url: '',
				sha256: ''
			}
		};

		if (latestJson[binary.arch]?.sha256 === binary.sha256 && latestJson[binary.arch]?.url) {
			// Reuse old URLs in case that SHA256 match
			newJson[binary.arch].url = latestJson[binary.arch]?.url;
		} else {
			// Otherwise release the file
			const resource = resourceName('binary', version, binary.arch);
			newJson[binary.arch].url = `https://github.com/metacall/guix/releases/download/v${version}/${resource}`;
			releaseFiles.push(binary.filePath);
		}
	}

	for (const cache of caches) {
		newJson[cache.arch].cache.sha256 = cache.sha256;

		if (latestJson[cache.arch]?.cache?.sha256 === cache.sha256 && latestJson[cache.arch]?.cache?.url) {
			// Reuse old URLs in case that SHA256 match
			newJson[cache.arch].cache.url = latestJson[cache.arch]?.cache?.url;
		} else {
			// Otherwise release the file
			const resource = resourceName('cache', version, cache.arch);
			newJson[cache.arch].cache.url = `https://github.com/metacall/guix/releases/download/v${version}/${resource}`;
			releaseFiles.push(cache.filePath);
		}
	}

	// Store the json
	const buildPath = path.join(hostOutput, 'build.json');

	await writeFile(buildPath, JSON.stringify(newJson, null, 2), 'utf8');

	// Fetch the latest channels.scm replacing the URL
	await fetchChannels(hostOutput);

	// Fetch the latest install.sh
	await fetchInstall(hostOutput);
};


// TODO: Replace build-refactor.json in the current release
// TODO: Make cache optional in the download target of Dockerfile
// TODO: Replace metacall/guix-binary by metacall/guix in Dockerfile

release();

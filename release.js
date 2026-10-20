#!/usr/bin/env node

const { spawn } = require('child_process');
const path = require('path');
const crypto = require('crypto');
const { createReadStream, createWriteStream } = require('fs');
const { mkdir, stat, readFile, writeFile, rename } = require('fs/promises');
const { Readable } = require('stream');
const { pipeline } = require('stream/promises');

const METACALL_GUIX = 'metacall/guix';

const createReleasePath = async () => {
	const releasePath = path.resolve(__dirname, '.release');
	await mkdir(releasePath, { recursive: true });
	return releasePath;
};

const fileExists = async filePath => {
	try {
		await stat(filePath);
		return true;
	} catch (err) {
		return false;
	}
};

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

// Define resource name
const resourceName = (resource, version, arch) => `guix-${resource}-${version}.${arch}.tar.xz`;

const defineVersion = async releasePath => {
	const versionPath = path.join(releasePath, 'VERSION');

	// If VERSION exists, load it
	if (await fileExists(versionPath)) {
		return await readFile(versionPath, 'utf-8');
	}

	// Otherwise generate it
	const version = new Date().toISOString().slice(0, 10).replace(/-/g, '');

	// Store the version
	await writeFile(versionPath, version, 'utf8');

	return version;
};

const runCommand = async (cmd, args = [], context) => {
	const command = `${cmd} ${args.join(' ')}`;

	// Print command
	console.log(command);

	// Execute command
	return new Promise((resolve, reject) => {
		const child = spawn(cmd, args, { shell: true});

		let stdout = '';
		let stderr = '';

		child.stdout.on('data', (data) => {
			stdout += data.toString();
		});

		child.stderr.on('data', (data) => {
			stderr += data.toString();
		});

		child.on('error', (error) => {
			reject(error);
		});

		child.on('close', (exitCode) => {
			resolve({
				context,
				cmd,
				args,
				stdout: stdout.trim(),
				stderr: stderr.trim(),
				exitCode
			});
		});
	});
};

const report = results => {
	results.forEach(result => {
		console.log(`----------------- ${JSON.stringify(result.context)} -----------------`);
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

		console.log(`Computing SHA256 of: ${filePath}`);

		stream.on('error', err => reject(err));
		stream.on('data', chunk => hash.update(chunk));
		stream.on('end', () => resolve(fn(hash.digest('hex'), context)));
	});
};

const latestRelease = async () => {
	const latestResponse = await fetch(`https://github.com/${METACALL_GUIX}/releases/latest`, {
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
	const filePath = path.join(outputDir, fileName);

	console.log(`Fetching file: ${url} => ${filePath}`);

	const response = await fetch(url);

	if (!response.ok) {
		throw new Error(`Failed to fetch ${fileName} from ${url}: ${response.status} ${response.statusText}`);
	}

	const streams = [
		Readable.fromWeb(response.body),
		transform,
		createWriteStream(filePath)
	].filter(Boolean);

    await pipeline(...streams);

	return filePath;
};

const fetchInstall = async outputDir => fetchFile(
	outputDir,
	'https://guix.gnu.org/install.sh',
	'install.sh'
);

const generateRelease = async (releasePath, releaseFiles) => {
	console.log(`Generating release into: ${releasePath}`);
	console.log(releaseFiles.join('\n'));

    const movePromises = releaseFiles.map(async file => {
      const fileName = path.basename(file);
      const targetPath = path.join(releasePath, fileName);
      await rename(file, targetPath);
    });

    return await Promise.all(movePromises);
};

const executeTasks = async tasks => {
	const results = await Promise.all(tasks);
	const errors = results.filter(result => result.exitCode != 0);

	if (errors.length > 0) {
		console.log('ERROR: While processing the following architectures:');
		report(errors);
		return errors;
	}

	report(results);
	return [];
};

const executeTasksWithRetry = async tasks => {
	const errors = await executeTasks(tasks);

	if (errors.length > 0) {
		// Retry the job, sometimes Guix is fragile and fails
		console.log(`Encountered ${errors.length} errors, retrying the failed tasks...`);
		const retryTasks = errors.map(error => runCommand(error.cmd, error.args, error.context));
		const retryErrors = await executeTasks(retryTasks);

		if (retryErrors.length > 0) {
			console.log(`Encountered ${retryErrors.length} errors while retrying, exiting...`);
			process.exit(1);
		}
	}
};

const findDockerHubLatestTags = async () => {
	const attempts = 3;

	for (let attempt = 1; attempt <= attempts; attempt++) {
		try {
			const response = await fetch(
				`https://registry.hub.docker.com/v2/repositories/${METACALL_GUIX}/tags?page_size=250`
			);

			if (!response.ok) {
				throw new Error(`Failed to fetch tags: ${response.status} ${response.statusText}`);
			}

			const data = await response.json();
			const tags = data.results.map(r => r.name);

			return tags;
		} catch (e) {
			console.log(`ERROR: Failed to download latest tags from DockerHub (attempt ${attempt} of ${attempts}):`, e);

			if (attempt < attempts) {
				// Back off before retrying, 30s and 60s
				await sleep(attempt * 30 * 1000);
			}
		}
	}

	return [];
};

const findLatestValidTag = async architecture => {
	// Check locally first
	const images = await runCommand('docker', [
		'images', '--format', '{{.Repository}}:{{.Tag}}'
	]);

	const localTags = images.stdout
		.split('\n')
		.filter(line => line.startsWith(`${METACALL_GUIX}:`));

	for (const image of localTags) {
		const inspect = await runCommand('docker', [
			'image', 'inspect', image
		]);

		if (inspect.exitCode !== 0) {
			continue;
		}

		const metadata = JSON.parse(inspect.stdout);

		const supportsArchitecture = metadata.some(
			img => `${img.Os}/${img.Architecture}` === architecture
		);

		if (supportsArchitecture) {
			// Return the valid tag
			return image.split(':').pop();
		}
	}

	// Start pulling from DockerHub
	const tags = await findDockerHubLatestTags();
	const attempts = 3;

	for (const tag of tags) {
		for (let attempt = 1; attempt <= attempts; attempt++) {
			const pull = await runCommand('docker', [
				'pull', `--platform=${architecture}`, `${METACALL_GUIX}:${tag}`
			]);

			if (pull.exitCode === 0) {
				if (tag !== tags[0]) {
					console.log(`Warning: ${architecture} not found in ${METACALL_GUIX}:${tags[0]}, using older tag ${METACALL_GUIX}:${tag}`);
				}

				return tag;
			}

			// The tag does not contain this architecture, try the next one
			if (/no matching manifest|manifest unknown/i.test(pull.stderr)) {
				break;
			}

			console.log(`ERROR: Failed to pull ${METACALL_GUIX}:${tag} for ${architecture} (attempt ${attempt} of ${attempts}): ${pull.stderr}`);

			if (attempt === attempts) {
				// Do not fall back to an older tag on network errors, it would release an outdated Guix
				return undefined;
			}

			// Back off before retrying, 30s and 60s
			await sleep(attempt * 30 * 1000);
		}
	}
};

const dependency = async (architectures) => {
	// Install QEMU for executing the images in multiple architectures
	if (architectures.length > 0) {
		const dependency = await runCommand('docker', [
			'run', '--rm', '--privileged',
			'multiarch/qemu-user-static',
			'--reset', '-p', 'yes'
		]);

		if (dependency.exitCode != 0) {
			throw Error(`Failed to install QEMU multiarch:
				${dependency.stdout}
				${dependency.stderr}
			`);
		}
	}
};

const build = async (architectures, { version, hostOutput, hostScripts, containerScripts }) => {
	// Build the images
	const containerOutput = '/output';

	// Find the latest valid tag
	const validArchitectures = [];

	for (const arch of architectures) {
		const tag = await findLatestValidTag(arch.docker);

		if (tag !== undefined) {
			validArchitectures.push({ ...arch, tag });
		} else {
			console.log(`Warning: No valid image found for ${arch.docker}, skipping ${arch.guix}`);
		}
	}

	// Define tasks for releasing for each architecture
	const tasks = validArchitectures.map(arch => {
		// Cache breaks for 32-bit file system (armhf-linux)
		const tmpfsCacheArgs = (arch.guix === 'armhf-linux')
			? ['-e', 'XDG_CACHE_HOME=/tmp/.cache', '--mount', 'type=tmpfs,target=/tmp/.cache']
			: [];

		const args = [
			'run', '--rm', '--privileged',
			'--name', `guix-build-${arch.guix}`,
			'-v', `${hostOutput}:${containerOutput}`,
			'-v', `${hostScripts}:${containerScripts}`,
			...tmpfsCacheArgs,
			'--platform', arch.docker,
			'-t', `${METACALL_GUIX}:${arch.tag}`,
			`${containerScripts}/release.sh`, arch.guix, containerOutput, version
		];

		return runCommand('docker', args, arch);
	});

	// Execute the tasks and print the results
	await executeTasksWithRetry(tasks);
};

const verify = async (architectures, { version, hostOutput }) => {
	// Build skips an architecture silently if it does not find a valid image,
	// so check that all the requested architectures produced their files
	const missing = [];

	for (const arch of architectures) {
		for (const resource of ['binary', 'cache']) {
			const filePath = path.join(hostOutput, resourceName(resource, version, arch.guix));

			if (!(await fileExists(filePath)) || (await stat(filePath)).size === 0) {
				missing.push(filePath);
			}
		}
	}

	if (missing.length > 0) {
		console.log(`ERROR: Missing or empty release files:\n${missing.join('\n')}`);
		process.exit(1);
	}
};

const skipMetaData = async () => {
	console.log('Skipping metadata generation...');
	process.exit(0);
};

const metadata = async (architectures, { releasePath, version, hostOutput }) => {
	console.log('Generating metadata...');

	// Get latest release download base URL
	const latestReleaseUrl = await latestRelease();

	// Get the latest build.json
	const latestJson = await fetchBuildJson(latestReleaseUrl);

	// Errors are reported at the end, so the release is generated with the resources available
	const errors = [];

	const error = message => {
		console.log(`ERROR: ${message}`);
		errors.push(message);
	};

	// Get the SHA256 of all files
	const computeSha256 = async resource => {
		const results = await Promise.all(architectures.map(arch => {
			const filePath = path.join(hostOutput, resourceName(resource, version, arch.guix));

			const compute = async () => {
				if (await fileExists(filePath)) {
					// If the file exists, calculate the SHA256
					return await sha256(filePath, (sha256, arch) => {
						return {
							arch,
							filePath,
							sha256
						};
					}, arch.guix);
				} else {
					// If the file does not exist, return the latest cached resource
					const previous = ({
						binary: latestJson[arch.guix],
						cache: latestJson[arch.guix]?.cache
					})[resource];

					// If there is no previous resource either, skip it
					if (!previous?.sha256 || !previous?.url) {
						// Missing caches are reported once build.json is generated, only for the architectures released
						if (resource === 'binary') {
							error(`Binary of ${arch.guix} not found and not available in last build.json, ${arch.guix} will be omitted from build.json`);
						}

						return null;
					}

					console.log(`Warning: Resource '${resource}' of ${arch.guix} not found, using previous resource from last build.json with SHA256: ${previous.sha256}`);

					return {
						arch: arch.guix,
						filePath,
						sha256: previous.sha256
					};
				}
			};

			return compute();
		}));

		return results.filter(result => result !== null);
	};

	const binaries = await computeSha256('binary');
	const caches = await computeSha256('cache');

	// Generate build.json with all the information and the files to release
	const newJson = {};
	const releaseFiles = [];

	for (const binary of binaries) {
		newJson[binary.arch] = {
			url: '',
			sha256: binary.sha256
		};

		if (latestJson[binary.arch]?.sha256 === binary.sha256 && latestJson[binary.arch]?.url) {
			// Reuse old URLs in case that SHA256 match
			newJson[binary.arch].url = latestJson[binary.arch]?.url;
		} else {
			// Otherwise release the file
			const resource = resourceName('binary', version, binary.arch);
			newJson[binary.arch].url = `https://github.com/${METACALL_GUIX}/releases/download/v${version}/${resource}`;
			releaseFiles.push(binary.filePath);
		}
	}

	for (const cache of caches) {
		// The cache is useless without its binary
		if (newJson[cache.arch] === undefined) {
			error(`Cache of ${cache.arch} is available but its binary is not, the cache will be omitted from build.json`);
			continue;
		}

		newJson[cache.arch].cache = {
			url: '',
			sha256: cache.sha256
		};

		if (latestJson[cache.arch]?.cache?.sha256 === cache.sha256 && latestJson[cache.arch]?.cache?.url) {
			// Reuse old URLs in case that SHA256 match
			newJson[cache.arch].cache.url = latestJson[cache.arch]?.cache?.url;
		} else {
			// Otherwise release the file
			const resource = resourceName('cache', version, cache.arch);
			newJson[cache.arch].cache.url = `https://github.com/${METACALL_GUIX}/releases/download/v${version}/${resource}`;
			releaseFiles.push(cache.filePath);
		}
	}

	for (const arch of Object.keys(newJson)) {
		if (newJson[arch].cache === undefined) {
			error(`Cache of ${arch} not found and not available in last build.json, ${arch} will be released without cache`);
		}
	}

	// Store the json
	const buildPath = path.join(hostOutput, 'build.json');
	await writeFile(buildPath, JSON.stringify(newJson, null, 2), 'utf8');
	releaseFiles.push(buildPath);

	// Fetch the latest install.sh
	const installPath = await fetchInstall(hostOutput);
	releaseFiles.push(installPath);

	// Move release files to the release path
	await generateRelease(releasePath, releaseFiles);

	if (errors.length > 0) {
		console.log(`ERROR: Release generated with ${errors.length} errors:\n${errors.join('\n')}`);
		process.exit(1);
	}
};

const docker = async architectures => {
	// Define tasks for building each image for each architecture
	const tasks = architectures.map(arch => {
		const args = [
			'buildx', 'build',
			'--progress=plain',
			'--platform', arch.docker,
			'--build-arg', `METACALL_GUIX_ARCH=${arch.guix}`,
			'--cache-from', `type=registry,ref=docker.io/${METACALL_GUIX}`,
			'-t', METACALL_GUIX,
			'--load',
			'--allow', 'security.insecure',
			'.'
		];

		return runCommand('docker', args, arch);
	});

	// Execute the tasks and print the results
	await executeTasksWithRetry(tasks);

	// Define the test path
	const testPath = path.resolve(__dirname, 'test');

	// Define tasks for testing the images
	const tests = architectures.map(arch => {
		const args = [
			'run', '--rm', '--privileged',
			'--pull=never',
			'--platform', arch.docker,
			'-v', `${testPath}/:/root/test/`,
			METACALL_GUIX,
			'bash', '/root/test/test.sh'
		];

		return runCommand(docker, args, arch);
	});

	// Execute the tasks and print the results
	await executeTasksWithRetry(tests);
};

const release = async ({ architectures, pipeline }) => {
	// Define context
	const releasePath = await createReleasePath();
	const version = await defineVersion(releasePath);
	const hostOutput = path.resolve(__dirname, 'out');
	const hostScripts = path.resolve(__dirname, 'scripts');
	const containerScripts = '/scripts';

	// Execute each step of the pipeline
	for (const step of pipeline) {
		await step(architectures, {
			releasePath,
			version,
			hostOutput,
			hostScripts,
			containerScripts
		});
	}
};

const parseArguments = () => {
	const architectures = [
		{ docker: 'linux/amd64', guix: 'x86_64-linux' },
		{ docker: 'linux/386', guix: 'i686-linux' },
		{ docker: 'linux/arm/v7', guix: 'armhf-linux' },
		{ docker: 'linux/arm64/v8', guix: 'aarch64-linux' },
		{ docker: 'linux/ppc64le', guix: 'powerpc64le-linux' },
		{ docker: 'linux/riscv64', guix: 'riscv64-linux' }
	];

	const args = process.argv.slice(2);

	// Without arguments, build the metadata
	if (args.length === 0) {
		console.log('No architecture detected, only metadata will be generated...');
		return {
			architectures,
			pipeline: [ metadata ]
		};
	}

	// With all argument, build all images and metadata
	if (args.length === 1) {
		if (args[0] === 'all') {
			console.log('All architectures detected, images and metadata will be generated...');
			return {
				architectures,
				pipeline: [ dependency, build, metadata ]
			};
		} else if (args[0] === 'docker') {
			console.log(`Docker detected, a new ${METACALL_GUIX} for all architectures with up to date pull will be built...`);
			return {
				architectures,
				pipeline: [ dependency, docker ]
			};
		}
	}

	// Otherwise, build the specified arquitecutres and avoid metadata, this allow parallel builds
	const argsArchitectures = architectures.filter(arch => args.includes(arch.guix));
	const guixArchitectures = argsArchitectures.map(arch => arch.guix);

	console.log(`${guixArchitectures.join(', ')} architectures detected, only images will be generated without metadata...`);

	return {
		architectures: argsArchitectures,
		pipeline: [ dependency, build, verify, skipMetaData ]
	};
};

const main = async () => {
	const options = parseArguments();

	return await release(options);
};

main();

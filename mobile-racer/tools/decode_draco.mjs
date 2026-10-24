#!/usr/bin/env node
/**
 * Decode KHR_draco_mesh_compression into standard glTF accessors so Godot's
 * native glTF importer can load the car models without a custom plugin.
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import { NodeIO } from '@gltf-transform/core';
import * as Extensions from '@gltf-transform/extensions';
import draco3d from 'draco3dgltf';

const root = path.resolve('mobile-racer');
const assetsDir = path.join(root, 'assets', 'cars');
const manifestFile = path.join(assetsDir, 'asset-manifest.json');
const manifest = JSON.parse(await fs.readFile(manifestFile, 'utf8'));
const decoder = await draco3d.createDecoderModule();
const extensionClasses = Object.values(Extensions)
  .filter((value) => typeof value === 'function' && typeof value.EXTENSION_NAME === 'string' && value.prototype && typeof value.prototype.register === 'function');
const io = new NodeIO()
  .registerExtensions(extensionClasses)
  .registerDependencies({ 'draco3d.decoder': decoder });

for (const model of manifest.models) {
  const file = path.join(assetsDir, model.file);
  const document = await io.read(file);
  const dracoExtension = document.getRoot().listExtensionsUsed()
    .find((extension) => extension.extensionName === 'KHR_draco_mesh_compression');
  if (dracoExtension) {
    dracoExtension.dispose();
    await io.write(file, document);
  }
  const bytes = await fs.readFile(file);
  const outputHash = await import('node:crypto').then(({createHash}) => createHash('sha256').update(bytes).digest('hex'));
  const jsonLength = bytes.readUInt32LE(12);
  const gltf = JSON.parse(bytes.subarray(20, 20 + jsonLength).toString('utf8'));
  const extensions = gltf.extensionsRequired || [];
  if (extensions.includes('KHR_draco_mesh_compression')) {
    throw new Error(`Draco extension remains after conversion: ${model.file}`);
  }
  model.upstream_sha256 = model.upstream_sha256 || model.sha256;
  model.sha256 = outputHash;
  model.size_bytes = bytes.length;
  model.draco_decoded_for_godot = true;
  console.log(`Decoded ${model.game_name}: ${bytes.length.toLocaleString()} bytes; Draco removed`);
}
await fs.writeFile(manifestFile, JSON.stringify(manifest, null, 2) + '\n');
console.log(`Decoded ${manifest.models.length} car models.`);

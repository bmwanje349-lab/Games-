#!/usr/bin/env node
/**
 * Convert pinned upstream GLBs into mobile-friendly Godot assets.
 * Draco is decoded, geometry is simplified conservatively, textures are resized
 * to a 1024 px maximum, and original attribution/source hashes remain recorded.
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { weld, simplify, dedup, prune, textureCompress } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';
import draco3d from 'draco3dgltf';

const root = path.resolve('mobile-racer');
const assetsDir = path.join(root, 'assets', 'cars');
const manifestFile = path.join(assetsDir, 'asset-manifest.json');
const manifest = JSON.parse(await fs.readFile(manifestFile, 'utf8'));
const decoder = await draco3d.createDecoderModule();
const io = new NodeIO()
  .registerExtensions(ALL_EXTENSIONS)
  .registerDependencies({ 'draco3d.decoder': decoder });

await MeshoptSimplifier.ready;

function gitGlbDocument(bytes) {
  if (bytes.toString('ascii', 0, 4) !== 'glTF') {
    throw new Error('File is not a GLB container');
  }
  const jsonLength = bytes.readUInt32LE(12);
  return JSON.parse(bytes.subarray(20, 20 + jsonLength).toString('utf8'));
}

function triangleCount(document) {
  let total = 0;
  for (const mesh of document.getRoot().listMeshes()) {
    for (const primitive of mesh.listPrimitives()) {
      if (primitive.getMode() !== 4) continue;
      const indices = primitive.getIndices();
      const position = primitive.getAttribute('POSITION');
      if (indices) total += Math.floor(indices.getCount() / 3);
      else if (position) total += Math.floor(position.getCount() / 3);
    }
  }
  return total;
}

for (const model of manifest.models) {
  const file = path.join(assetsDir, model.file);
  const originalBytes = await fs.readFile(file);
  const sourceHash = createHash('sha256').update(originalBytes).digest('hex');
  const document = await io.read(file);
  const beforeTriangles = triangleCount(document);
  model.upstream_sha256 = model.upstream_sha256 || model.sha256;
  model.source_size_bytes = originalBytes.length;

  // KHR_draco_mesh_compression is decoded when the document is read; remove the
  // now-unnecessary extension and retain ordinary glTF vertex/index buffers.
  const dracoExtension = document.getRoot().listExtensionsUsed()
    .find((extension) => extension.extensionName === 'KHR_draco_mesh_compression');
  if (dracoExtension) dracoExtension.dispose();

  // Keep the body silhouette/reflections detailed but reduce triangle and VRAM
  // load for phones. Texture source format is retained while the longest edge is
  // capped at 1024 pixels, suitable for a selected player vehicle.
  await document.transform(
    weld({ tolerance: 0.0001 }),
    simplify({ simplifier: MeshoptSimplifier, ratio: 0.68, error: 0.015 }),
    dedup(),
    prune(),
    textureCompress({ encoder: sharp, resize: [1024, 1024] }),
  );

  const afterTriangles = triangleCount(document);
  await io.write(file, document);
  const output = await fs.readFile(file);
  const outputDoc = gitGlbDocument(output);
  const required = outputDoc.extensionsRequired || [];
  if (required.includes('KHR_draco_mesh_compression')) {
    throw new Error('Draco extension remains after optimization: ' + model.file);
  }

  model.sha256 = createHash('sha256').update(output).digest('hex');
  model.size_bytes = output.length;
  model.triangles_before_optimization = beforeTriangles;
  model.triangles_after_optimization = afterTriangles;
  model.geometry_ratio = beforeTriangles > 0 ? Number((afterTriangles / beforeTriangles).toFixed(3)) : 1;
  model.draco_decoded_for_godot = true;
  model.mobile_optimized = true;
  console.log(
    model.game_name + ': ' + beforeTriangles.toLocaleString() + ' -> ' +
    afterTriangles.toLocaleString() + ' triangles; ' +
    originalBytes.length.toLocaleString() + ' -> ' +
    output.length.toLocaleString() + ' bytes',
  );
}
await fs.writeFile(manifestFile, JSON.stringify(manifest, null, 2) + '\n');
console.log('Decoded and optimized ' + manifest.models.length + ' attributed car models.');

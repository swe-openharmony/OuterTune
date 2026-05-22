// ====================================================================
// MockDataSource — read JSON seed data from rawfile/ at runtime.
//
// Realistic mock pattern: data ships in resources, page reads it via
// resourceManager + TextDecoder + JSON.parse (production-grade APIs).
// Swap with @ohos.data.relationalStore RDB later for SQL-backed mock.
// ====================================================================

import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

export class MockDataSource {
  /**
   * Loads and JSON-parses a rawfile asset. Throws on missing file or bad JSON.
   * Usage:   const data = await MockDataSource.loadJson<MyType>(this, 'mock_notebooks.json');
   */
  static async loadJson<T>(ctx: object, filename: string): Promise<T> {
    const ability = getContext(ctx) as common.UIAbilityContext;
    const buf: Uint8Array = await ability.resourceManager.getRawFileContent(filename);
    const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    const text = decoder.decodeToString(buf);
    return JSON.parse(text) as T;
  }
}

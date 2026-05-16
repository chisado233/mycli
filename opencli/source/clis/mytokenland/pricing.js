import { cli, Strategy } from '@jackwener/opencli/registry';
import { filterItems, getPricingData, pricingKind, pricingText } from './utils.js';

cli({
  site: 'mytokenland',
  name: 'pricing',
  description: 'Show MyTokenLand model pricing and supported endpoint types',
  domain: 'api.mytokenland.com',
  strategy: Strategy.PUBLIC,
  browser: false,
  args: [
    { name: 'query', type: 'str', required: false, positional: true, help: 'Optional model name filter' },
    { name: 'limit', type: 'int', default: 100, help: 'Maximum number of pricing rows to show' },
  ],
  columns: ['model', 'kind', 'pricing', 'endpoints', 'groups'],
  func: async (_page, args) => {
    const { status, items } = await getPricingData();
    return filterItems(items, args.query, args.limit).map(item => ({
      model: item.model_name,
      kind: pricingKind(item),
      pricing: pricingText(item, status.quota_per_unit),
      endpoints: Array.isArray(item.supported_endpoint_types) ? item.supported_endpoint_types.join(',') : '',
      groups: Array.isArray(item.enable_groups) ? item.enable_groups.join(',') : '',
    }));
  },
});

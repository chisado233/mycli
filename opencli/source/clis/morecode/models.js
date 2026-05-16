import { cli, Strategy } from '@jackwener/opencli/registry';
import { authenticatedRequest, filterItems, getPricingData, pricingText } from './utils.js';

cli({
  site: 'morecode',
  name: 'models',
  description: 'List models callable by the current MoreCode account',
  domain: 'www.1314mc.net:3333',
  strategy: Strategy.LOCAL,
  browser: false,
  args: [
    { name: 'query', type: 'str', required: false, positional: true, help: 'Optional model name filter' },
    { name: 'limit', type: 'int', default: 100, help: 'Maximum number of models to show' },
  ],
  columns: ['model', 'pricing', 'endpoints'],
  func: async (_page, args) => {
    const [{ data: modelData }, pricingData] = await Promise.all([
      authenticatedRequest('/api/user/models'),
      getPricingData(),
    ]);
    const models = Array.isArray(modelData.data) ? modelData.data : [];
    const pricingByName = new Map(pricingData.items.map(item => [item.model_name, item]));
    return filterItems(models.map(name => {
      const price = pricingByName.get(name) || {};
      return {
        model: name,
        pricing: price.model_name ? pricingText(price, pricingData.status.quota_per_unit) : '',
        endpoints: Array.isArray(price.supported_endpoint_types) ? price.supported_endpoint_types.join(',') : '',
      };
    }), args.query, args.limit);
  },
});

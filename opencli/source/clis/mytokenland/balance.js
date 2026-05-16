import { cli, Strategy } from '@jackwener/opencli/registry';
import { authenticatedRequest, formatUsd, getStatus, quotaToUsd } from './utils.js';

cli({
  site: 'mytokenland',
  name: 'balance',
  aliases: ['me'],
  description: 'Show MyTokenLand account balance and usage summary',
  domain: 'api.mytokenland.com',
  strategy: Strategy.LOCAL,
  browser: false,
  args: [],
  columns: ['username', 'group', 'quota', 'balance_usd', 'used_quota', 'used_usd', 'request_count'],
  func: async () => {
    const [profileResult, status] = await Promise.all([
      authenticatedRequest('/api/user/self'),
      getStatus(),
    ]);
    const user = profileResult.data.data || {};
    const quotaPerUnit = Number(status.quota_per_unit || 500000);
    const balanceUsd = quotaToUsd(user.quota, quotaPerUnit);
    const usedUsd = quotaToUsd(user.used_quota, quotaPerUnit);
    return [{
      username: user.username,
      group: user.group,
      quota: user.quota,
      balance_usd: balanceUsd == null ? '' : formatUsd(balanceUsd, 4),
      used_quota: user.used_quota,
      used_usd: usedUsd == null ? '' : formatUsd(usedUsd, 4),
      request_count: user.request_count,
    }];
  },
});

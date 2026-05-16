import { cli, Strategy } from '@jackwener/opencli/registry';
import { login } from './utils.js';

cli({
  site: 'morecode',
  name: 'login',
  description: 'Log in to MoreCode and verify the account credentials',
  domain: 'www.1314mc.net:3333',
  strategy: Strategy.LOCAL,
  browser: false,
  args: [],
  columns: ['username', 'display_name', 'id', 'group', 'role', 'status'],
  func: async () => {
    const { user } = await login();
    return [{
      username: user.username,
      display_name: user.display_name || '',
      id: user.id,
      group: user.group || '',
      role: user.role,
      status: user.status,
    }];
  },
});

import { cli, Strategy } from '@jackwener/opencli/registry';
import { DOUBAO_DOMAIN, getDoubaoTranscriptLines, getDoubaoVisibleTurns, sendDoubaoMessage, waitForDoubaoResponse } from './utils.js';
export const askCommand = cli({
    site: 'doubao',
    name: 'ask',
    description: 'Send a prompt and wait for the Doubao response',
    domain: DOUBAO_DOMAIN,
    strategy: Strategy.COOKIE,
    browser: true,
    navigateBefore: false,
    timeoutSeconds: 180,
    args: [
        { name: 'text', required: true, positional: true, help: 'Prompt to send' },
        { name: 'timeout', required: false, help: 'Max seconds to wait (default: 60)', default: '60' },
    ],
    columns: ['Role', 'Text'],
    func: async (page, kwargs) => {
        const text = kwargs.text;
        const timeout = parseInt(kwargs.timeout, 10) || 60;
        const beforeTurns = await getDoubaoVisibleTurns(page);
        const beforeLines = await getDoubaoTranscriptLines(page);
        await sendDoubaoMessage(page, text);
        const normalize = (value) => String(value || '').replace(/\s+/g, '').trim();
        const target = normalize(text);
        const getResponseAfterPrompt = async () => {
            const turns = await getDoubaoVisibleTurns(page);
            const promptIndex = [...turns]
                .map((turn, index) => ({ turn, index }))
                .reverse()
                .find(({ turn }) => turn.Role === 'User' && (normalize(turn.Text) === target
                || normalize(turn.Text).includes(target)
                || target.includes(normalize(turn.Text))))?.index ?? -1;
            if (promptIndex < 0)
                return '';
            return turns.slice(promptIndex + 1).find((turn) => turn.Role === 'Assistant')?.Text || '';
        };
        const previousAssistantResponses = new Set(beforeTurns
            .filter((turn) => turn.Role === 'Assistant')
            .map((turn) => turn.Text));
        const getNewestAssistantResponse = async () => {
            const turns = await getDoubaoVisibleTurns(page);
            return [...turns]
                .reverse()
                .find((turn) => turn.Role === 'Assistant' && !previousAssistantResponses.has(turn.Text))?.Text || '';
        };
        let response = '';
        let lastCandidate = '';
        let stableCount = 0;
        const pollIntervalSeconds = 2;
        const maxPolls = Math.max(1, Math.ceil(timeout / pollIntervalSeconds));
        for (let index = 0; index < maxPolls; index += 1) {
            await page.wait(index === 0 ? 1.5 : pollIntervalSeconds);
            await page.wait(0.3);
            const candidate = await getResponseAfterPrompt();
            if (!candidate) {
                const newestCandidate = await getNewestAssistantResponse();
                if (newestCandidate) {
                    response = newestCandidate;
                    break;
                }
                continue;
            }
            if (candidate === lastCandidate) {
                stableCount += 1;
            }
            else {
                lastCandidate = candidate;
                stableCount = 1;
            }
            if (stableCount >= 2 || index === maxPolls - 1) {
                response = candidate;
                break;
            }
        }
        if (!response) {
            for (let index = 0; index < 5; index += 1) {
                await page.wait(1);
                response = await getResponseAfterPrompt();
                if (response)
                    break;
            }
        }
        if (!response) {
            response = await waitForDoubaoResponse(page, beforeLines, beforeTurns, text, Math.min(5, timeout));
        }
        if (!response) {
            return [
                { Role: 'User', Text: text },
                { Role: 'System', Text: `No response within ${timeout}s. Doubao may still be generating.` },
            ];
        }
        return [
            { Role: 'User', Text: text },
            { Role: 'Assistant', Text: response },
        ];
    },
});


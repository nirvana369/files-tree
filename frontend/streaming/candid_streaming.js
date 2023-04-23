import { streamingCallbackHttpResponseType, Token } from './candid/candid_http';
import { IDL } from '@dfinity/candid';
import { concat, } from '@dfinity/agent';

const MAX_CALLBACKS = 1000;


export async function streamContent(agent, canisterId, streamingStrategy) {
    let buffer = new ArrayBuffer(0);
    let tokenOpt = [streamingStrategy.Callback.token];
    const [, callBackFunc] = streamingStrategy.Callback.callback;
    let currentCallback = 1;
    while (tokenOpt.length !== 0) {
        if (currentCallback > MAX_CALLBACKS) {
            throw new Error('Exceeded streaming callback limit');
        }
        const callbackResponse = await queryNextChunk(tokenOpt[0], agent, canisterId, callBackFunc);
        console.log(callbackResponse);
        switch (callbackResponse.status) {
            case "replied" /* Replied */: {
                const callbackData = IDL.decode([streamingCallbackHttpResponseType], callbackResponse.reply.arg)[0];
                console.log(callbackData);
                if (isStreamingCallbackResponse(callbackData)) {
                    buffer = concat(buffer, callbackData.body);
                    console.log(buffer.length);
                    tokenOpt = callbackData.token;
                    console.log(tokenOpt);
                }
                else {
                    throw new Error('Unexpected callback response: ' + callbackData);
                }
                break;
            }
            case "rejected" /* Rejected */: {
                throw new Error('Streaming callback error: ' + callbackResponse);
            }
        }
        currentCallback += 1;
    }
    return buffer;
}
function queryNextChunk(token, agent, canisterId, callBackFunc) {
    // const tokenType = token.type();
    // unbox primitive values
    const tokenValue = typeof token.valueOf === 'function' ? token.valueOf() : token;
    const callbackArg = IDL.encode([Token], [tokenValue]);
    return agent.query(canisterId, {
        methodName: callBackFunc,
        arg: callbackArg,
    });
}
function isStreamingCallbackResponse(response) {
    return (typeof response === 'object' &&
        response !== null &&
        'body' in response &&
        'token' in response);
}

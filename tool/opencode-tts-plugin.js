// MicroOS bridge: speak the final assistant response using Android's native TTS.
const spoken = new Set();

export const MicroOSTextToSpeech = async ({ client }) => ({
  event: async ({ event }) => {
    if (event?.type !== "session.idle") return;
    const sessionID =
      event?.properties?.sessionID ??
      event?.data?.sessionID ??
      event?.properties?.info?.id;
    if (!sessionID || spoken.has(sessionID)) return;

    try {
      const result = await client.session.messages({ path: { id: sessionID } });
      const messages = result?.data?.data ?? result?.data ?? [];
      const assistant = [...messages].reverse().find((item) =>
        item?.info?.role === "assistant" &&
        Array.isArray(item?.parts) &&
        item.parts.some((part) => part?.type === "text" && part?.text?.trim())
      );
      if (!assistant) return;

      const text = assistant.parts
        .filter((part) => part?.type === "text" && typeof part.text === "string")
        .map((part) => part.text)
        .join("\n")
        .trim();
      if (!text) return;

      // Keep this local to the Android device. Never send response text to a
      // remote speech provider or expose the bridge outside loopback.
      const response = await fetch("http://127.0.0.1:17842/speak", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ text }),
      });
      if (response.ok || response.status === 204) spoken.add(sessionID);
    } catch (error) {
      console.error("[microos-tts] could not hand response to Android TTS:", error);
    }
  },
});

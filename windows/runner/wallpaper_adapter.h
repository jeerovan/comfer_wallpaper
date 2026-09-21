#ifndef RUNNER_WALLPAPER_ADAPTER_H_
#define RUNNER_WALLPAPER_ADAPTER_H_

#include <flutter/method_call.h>
#include <flutter/method_result.h>
#include <flutter/encodable_value.h>

void HandleWallpaperCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

#endif

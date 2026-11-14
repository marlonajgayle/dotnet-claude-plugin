using FluentValidation;

namespace DvsaTemplate.Api.Infrastructure.Endpoints;

/// <summary>Runs the request's AbstractValidator before the handler: .WithValidation&lt;TRequest&gt;().</summary>
public sealed class ValidationFilter<TRequest> : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext context, EndpointFilterDelegate next)
    {
        var validator = context.HttpContext.RequestServices.GetService<IValidator<TRequest>>();
        var request = context.Arguments.OfType<TRequest>().FirstOrDefault();
        if (validator is null || request is null)
        {
            return await next(context);
        }

        var result = await validator.ValidateAsync(request, context.HttpContext.RequestAborted);
        return result.IsValid
            ? await next(context)
            : Results.ValidationProblem(result.ToDictionary());
    }
}

public static class ValidationFilterExtensions
{
    public static RouteHandlerBuilder WithValidation<TRequest>(this RouteHandlerBuilder builder) =>
        builder.AddEndpointFilter<ValidationFilter<TRequest>>();
}

namespace DvsaTemplate.Api.Infrastructure.Endpoints;

/// <summary>One endpoint per slice. Every implementation is found and mapped at startup.</summary>
public interface IEndpoint
{
    void MapEndpoint(IEndpointRouteBuilder app);
}
